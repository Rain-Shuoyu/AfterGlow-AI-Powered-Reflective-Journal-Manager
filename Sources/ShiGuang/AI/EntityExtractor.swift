import Foundation

// MARK: - Extracted entities

struct ExtractedEntities: Codable, Hashable, Sendable {
    var people: [String] = []
    var places: [String] = []
    var topics: [String] = []
    var moodKeywords: [String] = []

    /// Flattened set for fast overlap checks.
    var allPhrases: [String] {
        people + places + topics + moodKeywords
    }

    func phrases(of kind: EntityKind) -> [String] {
        switch kind {
        case .person:   return people
        case .place:    return places
        case .topic:    return topics
        case .mood:     return moodKeywords
        }
    }
}

enum EntityKind: String, CaseIterable, Hashable, Sendable {
    case person, place, topic, mood

    var displayName: String {
        switch self {
        case .person: return "人物"
        case .place:  return "地点"
        case .topic:  return "主题"
        case .mood:   return "情绪"
        }
    }
}

struct ExtractionRecord: Codable, Sendable {
    var extractedAt: Date
    var fileMTime: Date
    var entities: ExtractedEntities
}

// MARK: - Cache file on disk

struct ExtractionCacheFile: Codable, Sendable {
    var version: Int = 1
    /// Key is the standardized file path.
    var records: [String: ExtractionRecord] = [:]
}

// MARK: - Extractor

/// Calls the LLM to extract entities/topics from a diary entry.
/// Results are cached on disk keyed by file path + mtime — re-extraction
/// only happens for new or modified files.
final class EntityExtractor: @unchecked Sendable {
    static let shared = EntityExtractor()

    private let lock = NSLock()
    private let cacheURL: URL
    private var cache: ExtractionCacheFile
    private let concurrency: Int = 4

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ShiGuang", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheURL = dir.appendingPathComponent("entities.json")

        // Load cache (if any)
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode(ExtractionCacheFile.self, from: data) {
            self.cache = decoded
        } else {
            self.cache = ExtractionCacheFile()
        }
    }

    // MARK: - Public API

    /// Return cached extractions for the given entries. Entries whose file
    /// has been modified since the last extraction are NOT included.
    func cached(entries: [DiaryEntry]) -> [DiaryEntry.ID: ExtractedEntities] {
        lock.lock(); defer { lock.unlock() }
        var out: [DiaryEntry.ID: ExtractedEntities] = [:]
        for e in entries {
            let key = pathKey(for: e)
            if let rec = cache.records[key], let mTime = e.modifiedAt, rec.fileMTime == mTime {
                out[e.id] = rec.entities
            }
        }
        return out
    }

    /// Extract entities for the given entries. Already-cached entries are
    /// skipped; new/stale ones are sent to the LLM with bounded concurrency.
    /// `onProgress` is called with (done, total) from a background queue.
    func extractAll(
        entries: [DiaryEntry],
        settings: AppSettings,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [DiaryEntry.ID: ExtractedEntities] {
        // 1. Figure out which need extraction
        let toExtract: [DiaryEntry] = lock.withLock {
            entries.filter { e in
                let key = pathKey(for: e)
                guard let rec = cache.records[key], let mTime = e.modifiedAt else { return true }
                return rec.fileMTime != mTime
            }
        }

        // 2. Start with whatever's already cached
        var results = cached(entries: entries)
        let total = entries.count
        let alreadyDone = total - toExtract.count
        await MainActor.run { onProgress(alreadyDone, total) }
        guard !toExtract.isEmpty else { return results }

        // 3. Run LLM in parallel with bounded concurrency
        let client = try LLMClientFactory.make(settings: settings)
        try await withThrowingTaskGroup(of: (DiaryEntry, ExtractedEntities?).self) { group in
            var iterator = toExtract.makeIterator()
            var inFlight = 0
            var completed = alreadyDone

            // Seed the group
            for _ in 0..<min(concurrency, toExtract.count) {
                guard let next = iterator.next() else { break }
                inFlight += 1
                group.addTask { [self] in
                    let entities = try? await self.extractOne(entry: next, client: client)
                    return (next, entities)
                }
            }

            for try await (entry, entities) in group {
                inFlight -= 1
                completed += 1
                if let entities = entities {
                    results[entry.id] = entities
                }
                await MainActor.run { onProgress(completed, total) }
                if let next = iterator.next() {
                    inFlight += 1
                    group.addTask { [self] in
                        let e = try? await self.extractOne(entry: next, client: client)
                        return (next, e)
                    }
                }
            }
        }

        return results
    }

    /// Wipe the entire cache. Next call to extractAll re-extracts everything.
    func clearCache() {
        lock.lock(); defer { lock.unlock() }
        cache.records.removeAll()
        saveLocked()
    }

    // MARK: - Internals

    private func extractOne(entry: DiaryEntry, client: LLMClient) async throws -> ExtractedEntities {
        let prompt = Self.prompt(for: entry)
        let req = ChatRequest(
            messages: [ChatMessage(role: .user, content: prompt)],
            model: "MiniMax-M2.7",  // overridden by caller if needed
            temperature: 0,
            maxTokens: 500
        )
        let resp = try await client.chat(req)
        let entities = try Self.parse(resp.text)
        let mTime = entry.modifiedAt ?? Date()
        recordCacheSync(key: pathKey(for: entry), mTime: mTime, entities: entities)
        return entities
    }

    /// Nonisolated synchronous helper so the lock is never held across an
    /// `await` suspension point (Swift 6 strict concurrency).
    nonisolated private func recordCacheSync(key: String, mTime: Date, entities: ExtractedEntities) {
        lock.lock()
        cache.records[key] = ExtractionRecord(
            extractedAt: Date(),
            fileMTime: mTime,
            entities: entities
        )
        saveLocked()
        lock.unlock()
    }

    private func pathKey(for entry: DiaryEntry) -> String {
        entry.url.standardizedFileURL.path
    }

    private func saveLocked() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Prompt

    private static func prompt(for entry: DiaryEntry) -> String {
        """
        你的任务是从下面这篇日记中提取关键实体和主题，用于构建日记间的关系图谱。

        严格按以下 JSON 格式输出，不要任何解释、注释或额外文字（不要用 markdown 代码块包裹）：
        {"people":[""],"places":[""],"topics":[""],"moodKeywords":[""]}

        要求：
        1. 只提取日记正文中**明确出现**的人物、地点、主题、情绪描述
        2. 不要编造
        3. 每类最多 5 个最显著的，去重，使用原文中的中文表述
        4. 如果某类没有内容，返回空数组
        5. 主题用 2-4 字短语（如"骑行"、"阅读"、"工作焦虑"）

        日记标题：\(entry.title)
        日期：\(entry.date.short)

        正文：
        \(entry.plainText)
        """
    }

    // MARK: - Response parsing

    private static func parse(_ text: String) throws -> ExtractedEntities {
        // Find the first {...} JSON object in the response
        guard let openIdx = text.firstIndex(of: "{"),
              let closeIdx = lastBalancedBrace(in: text, startingFrom: openIdx) else {
            throw NSError(domain: "EntityExtractor", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "LLM 响应里没找到 JSON：\(text.prefix(200))"
            ])
        }
        let jsonStr = String(text[text.index(after: openIdx)...closeIdx])
        guard let data = jsonStr.data(using: .utf8) else {
            throw NSError(domain: "EntityExtractor", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "JSON 编码失败"
            ])
        }
        // The LLM sometimes wraps the string lists as `["a", "b"]` (good) but
        // occasionally includes trailing commas or comments. Be lenient.
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ExtractedEntities.self, from: data)
        } catch {
            // Try one more thing: fix trailing commas
            let fixed = jsonStr.replacingOccurrences(
                of: #",\s*([}\]])"#,
                with: "$1",
                options: .regularExpression
            )
            if let fdata = fixed.data(using: .utf8) {
                return try decoder.decode(ExtractedEntities.self, from: fdata)
            }
            throw error
        }
    }

    private static func lastBalancedBrace(in s: String, startingFrom start: String.Index) -> String.Index? {
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            let c = s[idx]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}

// MARK: - Tiny lock helper

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
