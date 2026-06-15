import Foundation

/// "📓 自我追问" LLM service.
///
/// On cache miss (or "换一批" press), it sends a batched prompt
/// to the LLM asking it to find 5-8 unresolved / definition /
/// emotion questions hidden in the user's recent writing. The
/// response is JSON-parsed into `[SelfQuestion]`.
///
/// Cache strategy:
///   - File: `~/Library/Application Support/ShiGuang/self-questions.json`
///   - TTL: 30 days (configurable). User can force a refresh
///     by tapping "换一批" in the UI.
///   - On startup / first display, the service returns the
///     cached set if it's < TTL, otherwise it refetches.
///
/// Privacy: the cached file contains the question *text* (which
/// is plain Chinese, no diary body). The diary body is only
/// sent to the LLM during a refresh — never persisted.
@MainActor
final class SelfQuestionService: ObservableObject {

    @Published private(set) var questions: [SelfQuestion] = []
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshed: Date?

    private let settingsStore: SettingsStore
    private let cacheURL: URL

    private static let cacheTTL: TimeInterval = 30 * 24 * 60 * 60    // 30 days

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        // ~/Library/Application Support/ShiGuang/self-questions.json
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("ShiGuang", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        self.cacheURL = folder.appendingPathComponent("self-questions.json")
        loadFromCache()
    }

    // MARK: - Public

    /// Return cached questions. If the cache is stale (or
    /// empty), trigger a refresh in the background and return
    /// the stale set in the meantime (better than blocking the
    /// UI on a 30s LLM call).
    func cachedOrRefresh(entries: [DiaryEntry]) {
        if isCacheFresh() {
            return
        }
        Task { await refresh(entries: entries) }
    }

    /// Force a refresh — bypass cache. Called by the "换一批"
    /// button.
    func refresh(entries: [DiaryEntry]) async {
        guard !entries.isEmpty else {
            self.questions = []
            saveCache()
            return
        }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let newQuestions = try await fetchQuestions(entries: entries)
            self.questions = newQuestions
            self.lastRefreshed = Date()
            saveCache()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Mark a question as answered by the user (or skipped).
    /// For now we just remove it from the visible list; the
    /// cache will be regenerated on the next refresh.
    func dismissQuestion(_ id: String) {
        questions.removeAll { $0.id == id }
        saveCache()
    }

    // MARK: - LLM call

    private func fetchQuestions(entries: [DiaryEntry]) async throws -> [SelfQuestion] {
        let client = try LLMClientFactory.make(settings: settingsStore.settings)

        // Sample up to 30 most recent entries. We send the
        // frontmatter + first 2 paragraphs of body to keep the
        // prompt under ~6k tokens.
        let recent = Array(entries
            .sorted { $0.date > $1.date }
            .prefix(30))
        let corpus = recent.map { e -> String in
            let head = e.rawContent
                .components(separatedBy: "\n\n")
                .prefix(2)
                .joined(separator: "\n\n")
            let trimmed = head.count > 500
                ? String(head.prefix(500)) + "…"
                : head
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return "[\(f.string(from: e.date))] \(trimmed)"
        }.joined(separator: "\n\n---\n\n")

        let system = """
            你是"拾光"里的自我追问助手。你的唯一任务是：通读用户最近的日记，找出**5-8 个他们还没回答、值得被追问**的问题。
            严格只输出 JSON 数组，不要 markdown 代码块，不要任何解释。
            每个问题的字段：
            - "kind": "unresolved"（悬而未决，比如想做某个决定、说过要做什么但没写后续）、"definition"（自我定义，比如反复提到同一个词，问那是什么）、"emotion"（情绪主题，比如反复出现某种情绪）
            - "text": 30-80 字的中文问句。要温和、不评判、不带建议。问 ta 自己。
            - "source_date": 若是 unresolved 就填来源日期（YYYY-MM-DD），否则 null
            - "source_entry_id": 若是 unresolved 就填来源 entry id，否则 null

            风格：像朋友轻轻问一句"诶，那个决定后来呢？"。
            禁止：心理学术语、说教、鸡汤、引用名人、给建议。

            输出格式（严格 JSON）：
            [
              {"kind": "unresolved", "text": "...", "source_date": "2026-04-12", "source_entry_id": "<id>"},
              ...
            ]
            """

        let req = ChatRequest(
            messages: [
                ChatMessage(role: .system, content: system),
                ChatMessage(role: .user, content: corpus)
            ],
            model: settingsStore.settings.model,
            temperature: 0.8,
            maxTokens: 1500
        )

        let response = try await client.chat(req)
        return parseQuestions(json: response.text, entries: recent)
    }

    private func parseQuestions(json: String, entries: [DiaryEntry]) -> [SelfQuestion] {
        // Defensive: strip ```json ... ``` fences if the model
        // ignored the "no markdown" instruction.
        var cleaned = json
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Drop the first line (```json) and the last ``` line
            if let firstNL = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNL)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        guard let arr = raw as? [[String: Any]] else { return [] }

        let now = Date()
        return arr.enumerated().compactMap { (i, obj) -> SelfQuestion? in
            guard let kindStr = obj["kind"] as? String,
                  let kind = SelfQuestion.Kind(rawValue: kindStr),
                  let text = obj["text"] as? String
            else { return nil }
            let sourceDate = parseDate(obj["source_date"] as? String)
            let sourceEntryId = obj["source_entry_id"] as? String
            return SelfQuestion(
                id: "q\(i)_\(Int(now.timeIntervalSince1970))",
                kind: kind,
                text: text,
                sourceDate: sourceDate,
                sourceEntryId: sourceEntryId,
                createdAt: now
            )
        }
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    // MARK: - Cache

    private func isCacheFresh() -> Bool {
        guard let last = lastRefreshed else { return false }
        return Date().timeIntervalSince(last) < Self.cacheTTL
            && !questions.isEmpty
    }

    private struct CacheEnvelope: Codable {
        var questions: [SelfQuestion]
        var lastRefreshed: Date
    }

    private func loadFromCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let env = try? JSONDecoder().decode(CacheEnvelope.self, from: data)
        else { return }
        self.questions = env.questions
        self.lastRefreshed = env.lastRefreshed
    }

    private func saveCache() {
        let env = CacheEnvelope(questions: questions, lastRefreshed: lastRefreshed ?? Date())
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
