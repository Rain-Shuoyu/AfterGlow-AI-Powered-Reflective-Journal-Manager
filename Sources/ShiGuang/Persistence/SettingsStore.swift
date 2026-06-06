import Foundation

/// Persists `AppSettings` in UserDefaults, and the API key in macOS Keychain.
/// We deliberately keep these separate — UserDefaults plist files sync to iCloud
/// by default and are easy to dump, while Keychain is the right home for secrets.
final class SettingsStore: ObservableObject {
    @MainActor static let shared = SettingsStore()

    private let defaultsKey = "DiaryInsight.AppSettings.v1"
    private let keychainService = "com.diaryinsight.apikey"
    private let keychainAccount = "default"

    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        self.settings = Self.load()
    }

    /// Internal init for SwiftUI Previews / tests.
    init(initial: AppSettings) {
        self.settings = initial
    }

    // MARK: - Persistence

    private static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "DiaryInsight.AppSettings.v1"),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings.default
        }
        decoded = Self.migrate(decoded)
        decoded.apiKey = Keychain.read(service: "com.diaryinsight.apikey", account: "default") ?? ""
        return decoded
    }

    /// Bring older saved settings up to `AppSettings.currentSchemaVersion`.
    /// - v1 → v2: snap LLM provider/baseURL/model to the new defaults (MiniMax Mavis gateway).
    /// - v2 → v3: re-snap to the corrected MiniMax defaults (public api.minimax.chat / M2.7).
    ///            User customisations like temperature, diaryFolderPath, system prompt,
    ///            and the Keychain-stored API key are preserved.
    private static func migrate(_ s: AppSettings) -> AppSettings {
        var settings = s
        if settings.schemaVersion < 2 {
            settings.provider = .minimax
            settings.baseURL = AppSettings.LLMProvider.minimax.defaultBaseURL
            settings.model = AppSettings.LLMProvider.minimax.defaultModel
            settings.schemaVersion = 2
        }
        if settings.schemaVersion < 3 {
            // The Mavis-internal gateway URL we used in v2 is NOT the same as
            // the public minimaxi.com console API. v3 points at the public endpoint.
            settings.baseURL = AppSettings.LLMProvider.minimax.defaultBaseURL
            settings.model = AppSettings.LLMProvider.minimax.defaultModel
            settings.schemaVersion = 3
        }
        if settings.schemaVersion != AppSettings.currentSchemaVersion {
            // Persist the migrated settings so the migration only runs once.
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "DiaryInsight.AppSettings.v1")
            }
        }
        return settings
    }

    private func save() {
        var copy = settings
        let key = copy.apiKey
        copy.apiKey = ""   // never write the key to UserDefaults
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        if !key.isEmpty {
            Keychain.write(key, service: keychainService, account: keychainAccount)
        }
    }

    func reset() {
        settings = AppSettings.default
    }
}

// MARK: - Minimal Keychain wrapper
// We deliberately avoid importing Security as a heavy framework and just use the
// `security` CLI via Process for portability. For a sandboxed Mac App Store build
// you'd want to swap this for `SecItemAdd` etc. — keep this layer thin.
enum Keychain {
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        let proc = Process()
        proc.launchPath = "/usr/bin/security"
        proc.arguments = [
            "add-generic-password",
            "-a", account,
            "-s", service,
            "-w", value,
            "-U"   // update if exists
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func read(service: String, account: String) -> String? {
        let proc = Process()
        proc.launchPath = "/usr/bin/security"
        proc.arguments = [
            "find-generic-password",
            "-a", account,
            "-s", service,
            "-w"   // print password only
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let data = try? pipe.fileHandleForReading.readToEnd(),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func delete(service: String, account: String) {
        let proc = Process()
        proc.launchPath = "/usr/bin/security"
        proc.arguments = [
            "delete-generic-password",
            "-a", account,
            "-s", service
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }
}
