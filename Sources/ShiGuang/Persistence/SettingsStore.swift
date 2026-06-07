import Foundation
import Security

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
        // Pull the API key out of the Keychain. If missing, the user just
        // hasn't set one yet — that's a valid empty state, no crash.
        decoded.apiKey = Keychain.read(service: "com.diaryinsight.apikey", account: "default") ?? ""
        return decoded
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
        // Also wipe the keychain entry so "reset" truly means reset.
        Keychain.delete(service: keychainService, account: keychainAccount)
    }
}

// MARK: - Keychain wrapper (Security framework, no subprocess)
// The previous implementation shelled out to `/usr/bin/security` which on
// macOS 26 can pop a keychain-access GUI dialog on the main thread and
// trigger an AttributeGraph watchdog abort. In-process Security
// framework calls avoid both the GUI prompt and the cross-process dance.
enum Keychain {
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Remove any existing entry under the same service+account so
        // SecItemAdd doesn't bail with errSecDuplicateItem.
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        // After-first-unlock is the right accessibility for a CLI-style
        // helper app that might be launched before the user logs in.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // errSecItemNotFound is the normal "no key yet" case — return nil
        // without raising.
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
