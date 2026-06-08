import Foundation
import NaturalLanguage

/// Lightweight, on-device semantic retrieval built on Apple's NaturalLanguage
/// framework. No external API, no model download, no extra dependencies — just
/// `NLEmbedding.wordEmbedding(for: .simplifiedChinese)` averaged over the
/// tokenised text and L2-normalised, then ranked by cosine similarity.
///
/// Why this exists: the diary set is small (10s–1000s of entries), queries
/// are time-bounded Chinese, and a hand-rolled keyword+substring filter
/// misses synonyms, paraphrases, and partial matches. NLEmbedding gives us
/// real semantic matching with zero infra cost.
final class EmbeddingIndex: @unchecked Sendable {
    static let shared = EmbeddingIndex()

    // MARK: - Cache
    //
    // We persist per-entry embeddings to disk keyed by file path. A 16-char
    // content hash gates invalidation: if the file's title / tags / first
    // 500 chars change, the hash changes and we recompute. Cache lives at
    // `~/Library/Application Support/ShiGuang/embeddings.json` (same root
    // as the recycle bin).

    private struct EntryEmbedding: Codable {
        let contentHash: String
        let vector: [Double]
    }

    private let cacheURL: URL
    private var cache: [String: EntryEmbedding] = [:]
    private let cacheQueue = DispatchQueue(label: "ShiGuang.EmbeddingIndex", qos: .userInitiated)

    // MARK: - Init

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("ShiGuang", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("embeddings.json")
        loadCache()
    }

    /// Resolved embedding for the user's most likely language. Nil if the
    /// device doesn't have a model for it (older macOS, unsupported locale).
    /// We probe simplified Chinese first because the diary corpus is
    /// primarily Chinese, then fall back to English, then bail.
    private let embedding: NLEmbedding? = {
        if let zh = NLEmbedding.wordEmbedding(for: .simplifiedChinese) {
            return zh
        }
        if let en = NLEmbedding.wordEmbedding(for: .english) {
            return en
        }
        return nil
    }()

    var isAvailable: Bool { embedding != nil }

    // MARK: - Embed

    /// Tokenise `text` with the same CJK-aware word tokeniser used by the
    /// stats engine, look up each token's word vector, drop OOV tokens,
    /// average the rest, L2-normalise. Returns nil when no in-vocabulary
    /// token was found (e.g. a question written entirely in emoji / numbers).
    func embed(_ text: String) -> [Double]? {
        guard let embedding = embedding else { return nil }
        let cleaned = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = cleaned
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: cleaned.startIndex..<cleaned.endIndex) { range, _ in
            let token = String(cleaned[range])
            // Skip very short tokens and stopwords (reuse the same stopword
            // set as the word-cloud pipeline for consistency).
            guard token.count >= 2,
                  !StatisticsEngine.stopwords.contains(token) else {
                return true
            }
            if let v = embedding.vector(for: token) {
                // NLEmbedding returns nil for OOV but the vector() call can
                // also return an all-zeros vector for some edge cases — we
                // check by looking at the dimension and skip empty ones.
                if v.contains(where: { $0 != 0 }) {
                    vectors.append(v)
                }
            }
            return true
        }
        guard let first = vectors.first else { return nil }
        let dim = first.count
        var avg = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim { avg[i] += v[i] }
        }
        let n = Double(vectors.count)
        for i in 0..<dim { avg[i] /= n }
        // L2 normalise so dot product == cosine similarity.
        var norm = 0.0
        for x in avg { norm += x * x }
        norm = sqrt(norm)
        guard norm > 0 else { return nil }
        for i in 0..<dim { avg[i] /= norm }
        return avg
    }

    /// Stable content hash. Used to invalidate the cache when an entry
    /// changes (title, tags, or first 500 chars of body). 16 hex chars is
    /// plenty — collisions only cause a recompute, never a wrong result.
    private func contentHash(_ s: String) -> String {
        var h = Hasher()
        h.combine(s)
        let v = UInt64(bitPattern: Int64(h.finalize()))
        return String(v, radix: 16, uppercase: false)
    }

    /// Embed the canonical text of an entry (title + tags + first 500
    /// chars of body). Reads from the on-disk cache; recomputes and
    /// updates the cache when the content has changed.
    func embeddingForEntry(_ entry: DiaryEntry) -> [Double]? {
        let key = entry.url.path
        let canonical = canonicalText(for: entry)
        let hash = contentHash(canonical)
        if let hit = cache[key], hit.contentHash == hash {
            return hit.vector
        }
        guard let v = embed(canonical) else { return nil }
        cache[key] = EntryEmbedding(contentHash: hash, vector: v)
        return v
    }

    /// What we actually feed the embedder for an entry. Truncating to 500
    /// chars keeps the cache small and the computation fast — early
    /// sentences carry the most topical signal anyway.
    private func canonicalText(for entry: DiaryEntry) -> String {
        let head = String(entry.plainText.prefix(500))
        let tags = entry.frontmatter.tags.joined(separator: " ")
        return [entry.title, tags, head].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Similarity

    /// Dot product of two L2-normalised vectors == cosine similarity.
    /// Inputs are guaranteed unit-length from `embed(_:)` so this is
    /// safe and cheap (no sqrt).
    @inline(__always)
    func similarity(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        var s = 0.0
        for i in 0..<n { s += a[i] * b[i] }
        return s
    }

    // MARK: - Persistence

    /// Flush the cache to disk. Safe to call from any thread; writes are
    /// serialised on `cacheQueue`. Cheap (single small JSON file).
    func saveCache() {
        cacheQueue.async { [cache, cacheURL] in
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(cache) else { return }
            // Atomic write so a crash mid-save never leaves a half-baked file.
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: EntryEmbedding].self, from: data)
        else { return }
        cache = decoded
    }
}
