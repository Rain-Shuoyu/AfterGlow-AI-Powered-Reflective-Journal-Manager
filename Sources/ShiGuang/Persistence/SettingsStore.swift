import Foundation

/// We deliberately keep these separate — UserDefaults plist files sync to iCloud
/// by default and are easy to dump, while Keychain is the right home for secrets.
final class SettingsStore: ObservableObject {
    @MainActor static let shared = SettingsStore()

    private let defaultsKey = "DiaryInsight.AppSettings.v1"

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
        // The API key lives in the same UserDefaults blob as the rest of
        // AppSettings. Trade-off: it's visible in
        // ~/Library/Preferences/com.diaryinsight.app.plist. For a single-
        // user personal diary app this is acceptable; we trade Keychain's
        // first-time GUI prompt for the simpler in-process read.
        guard let data = UserDefaults.standard.data(forKey: "DiaryInsight.AppSettings.v1"),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings.default
        }
        // Migration: older builds stored the Mavis internal gateway
        // (`agent.minimaxi.com/mavis/api/v1/...`) as the .minimax baseURL.
        // That endpoint expects Mavis daemon keys, not the public
        // console API key the user just pasted — every call returns
        // 1004 / 401 even with a valid key. Silently upgrade anyone who
        // still has the old value.
        if decoded.provider == .minimax &&
           decoded.baseURL.contains("agent.minimaxi.com") {
            decoded.baseURL = AppSettings.LLMProvider.minimax.defaultBaseURL
            decoded.model   = AppSettings.LLMProvider.minimax.defaultModel
        }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reset() {
        settings = AppSettings.default
    }
}
