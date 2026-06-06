import Foundation

/// User-facing settings, persisted via `SettingsStore`. API key lives in Keychain,
/// not in this struct (so it never touches UserDefaults / plist files).
struct AppSettings: Codable, Equatable {
    /// Bumped any time the on-disk shape or default values change.
    /// `SettingsStore.load()` runs migrations if the saved version is older.
    static let currentSchemaVersion = 3

    var schemaVersion: Int = AppSettings.currentSchemaVersion

    // MARK: - Backwards-compatible decoding
    // Older saved blobs (v1, pre-schemaVersion) don't have a `schemaVersion` key,
    // and the new field would otherwise cause a hard decode failure that wipes the
    // user's diary folder path. Customise init(from:) to treat missing keys as
    // schema-version 1 so the migration in `SettingsStore.migrate(_:)` can upgrade
    // them in place.
    enum CodingKeys: String, CodingKey {
        case schemaVersion, diaryFolderPath, provider, baseURL, apiKey, model,
             maxContextEntries, temperature, systemPromptAddition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion       = (try? c.decodeIfPresent(Int.self,    forKey: .schemaVersion))       ?? 1
        self.diaryFolderPath     =  try? c.decodeIfPresent(String.self,  forKey: .diaryFolderPath)
        self.provider            = (try? c.decodeIfPresent(LLMProvider.self, forKey: .provider))        ?? .minimax
        self.baseURL             = (try? c.decodeIfPresent(String.self,  forKey: .baseURL))            ?? LLMProvider.minimax.defaultBaseURL
        self.apiKey              = (try? c.decodeIfPresent(String.self,  forKey: .apiKey))             ?? ""
        self.model               = (try? c.decodeIfPresent(String.self,  forKey: .model))              ?? LLMProvider.minimax.defaultModel
        self.maxContextEntries   = (try? c.decodeIfPresent(Int.self,     forKey: .maxContextEntries))  ?? 30
        self.temperature         = (try? c.decodeIfPresent(Double.self,  forKey: .temperature))        ?? 0.3
        self.systemPromptAddition = (try? c.decodeIfPresent(String.self, forKey: .systemPromptAddition)) ?? ""
    }

    init() {}
    enum LLMProvider: String, Codable, CaseIterable, Identifiable {
        case minimax
        case openAI
        case anthropic
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .minimax: return "MiniMax 官方 (M2.7)"
            case .openAI: return "OpenAI 兼容 (Chat Completions)"
            case .anthropic: return "Anthropic (Messages)"
            }
        }

        /// Default base URL for the provider's hosted API. Always overridable in Settings.
        var defaultBaseURL: String {
            switch self {
            case .minimax: return "https://api.minimax.chat"
            case .openAI: return "https://api.openai.com"
            case .anthropic: return "https://api.anthropic.com"
            }
        }

        /// Default model name for the provider.
        var defaultModel: String {
            switch self {
            case .minimax: return "MiniMax-M2.7"
            case .openAI: return "gpt-4o-mini"
            case .anthropic: return "claude-3-5-sonnet-latest"
            }
        }
    }

    var diaryFolderPath: String?     // security-scoped bookmark in production; we use plain path for SPM build
    var provider: LLMProvider = .minimax
    var baseURL: String = LLMProvider.minimax.defaultBaseURL
    var apiKey: String = ""          // mirrors Keychain value, kept in memory only after load
    var model: String = LLMProvider.minimax.defaultModel
    var maxContextEntries: Int = 30  // cap how many entries get sent to the LLM per query
    var temperature: Double = 0.3
    var systemPromptAddition: String = ""   // user-customisable extra system instructions

    static let `default` = AppSettings()

    /// Default settings per provider, used as presets when the user switches.
    static func defaults(for provider: LLMProvider) -> AppSettings {
        var s = AppSettings.default
        s.provider = provider
        s.baseURL = provider.defaultBaseURL
        s.model = provider.defaultModel
        return s
    }
}
