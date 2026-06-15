import Foundation
import NaturalLanguage

/// "🪞 镜像回放" — pick 5-7 sentences from the user's past
/// diary that feel "echoed back" to them.
///
/// Two sampler modes:
///   - `.random` (default): 8-12 random recent entries, then
///     diversity sampling so the final 5-7 sentences don't all
///     cover the same topic.
///   - `.themed(topic: String)`: pull sentences whose embedding
///     is closest to a topic string. This is the "回忆一下工作"
///     mode.
///
/// **Diversity sampling** is the interesting part. We want the
/// 5-7 sentences to feel like *different* moments, not 5
/// near-duplicates of the same mood. We use a simple greedy
/// MMR-style selection (Maximal Marginal Relevance):
///   1. Pick the entry whose embedding is closest to the
///      centroid of the random pool — that's our "anchor".
///   2. From the remaining entries, pick the one whose
///      embedding is *least similar* to what we've already
///      picked (MMR λ=0 = pure diversity).
///   3. Repeat until we have 5-7 sentences.
///
/// This is O(N²) for N=8-12 which is trivial.
struct MirrorReflection: Identifiable, Hashable {
    let id: String
    let text: String           // 1 line, 30-80 chars
    let sourceDate: Date       // date of the diary entry
    let sourceEntryId: String
    let sourceEntryTitle: String
}

enum MirrorSampler {

    enum Mode: Hashable {
        case random
        case themed(topic: String)
    }

    /// Sampling configuration. Defaults are tuned for a
    /// 5-7-sentence reflection.
    struct Config {
        var entryWindowDays: Int = 180       // look at the last N days
        var minEntries: Int = 5              // need at least this many to sample
        var maxEntries: Int = 12             // pull at most this many into the pool
        var outputCount: Int = 6             // 5-7 sentences is the sweet spot
        var maxCharsPerSentence: Int = 80
        var minCharsPerSentence: Int = 12
        var mmrLambda: Double = 0.0          // 0 = pure diversity, 1 = pure relevance
    }

    /// Sample a `MirrorReflection` set from `entries` using the
    /// given mode. Returns nil if there aren't enough entries.
    static func sample(
        from entries: [DiaryEntry],
        mode: Mode,
        config: Config = Config(),
        now: Date = Date()
    ) -> [MirrorReflection] {
        // 1. Filter to the time window.
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -config.entryWindowDays, to: now)
        else { return [] }
        let candidates = entries.filter { $0.date >= cutoff }
        guard candidates.count >= config.minEntries else { return [] }

        // 2. Pick the pool.
        let pool: [DiaryEntry] = {
            if candidates.count <= config.maxEntries {
                return Array(candidates)
            } else {
                // Random sample of maxEntries entries
                return Array(candidates.shuffled().prefix(config.maxEntries))
            }
        }()

        // 3. Get embeddings.
        // For .random we use the pool's centroid; for .themed we
        // embed the topic string.
        guard let embedding = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
        else { return fallbackSample(from: pool, config: config) }

        let poolVecs: [(DiaryEntry, [Double])] = pool.compactMap { e in
            let v = averageVector(for: e.rawContent, embedding: embedding)
            return v.map { (e, $0) }
        }
        guard poolVecs.count >= config.minEntries else {
            return fallbackSample(from: pool, config: config)
        }

        // 4. Compute the query vector.
        let queryVec: [Double]
        switch mode {
        case .random:
            // Centroid of pool
            queryVec = centroid(of: poolVecs.map { $0.1 })
        case .themed(let topic):
            guard let v = averageVector(for: topic, embedding: embedding) else {
                return fallbackSample(from: pool, config: config)
            }
            queryVec = v
        }

        // 5. Pick the first sentence (closest to query).
        let ranked = poolVecs.sorted { lhs, rhs in
            cosine(queryVec, lhs.1) > cosine(queryVec, rhs.1)
        }
        var picked: [(DiaryEntry, [Double])] = [ranked[0]]
        var pickedVecs: [[Double]] = [ranked[0].1]

        // 6. Greedy MMR for the rest.
        while picked.count < config.outputCount {
            var best: (DiaryEntry, [Double])? = nil
            var bestScore: Double = -.infinity
            for candidate in poolVecs where !picked.contains(where: { $0.0.id == candidate.0.id }) {
                let relevance = cosine(queryVec, candidate.1)
                // Diversity: 1 - max similarity to any already-picked
                let maxSimToPicked = pickedVecs.map { cosine(candidate.1, $0) }.max() ?? 0
                let diversity = 1.0 - maxSimToPicked
                let score = config.mmrLambda * relevance + (1.0 - config.mmrLambda) * diversity
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
            if let b = best {
                picked.append(b)
                pickedVecs.append(b.1)
            } else {
                break
            }
        }

        // 7. For each picked entry, extract the best sentence
        //    (closest to that entry's embedding, with a length
        //    preference).
        var reflections: [MirrorReflection] = []
        for (entry, vec) in picked {
            if let r = pickSentence(from: entry.rawContent,
                                    entryVec: vec,
                                    embedding: embedding,
                                    config: config) {
                reflections.append(MirrorReflection(
                    id: "\(entry.id)#\(reflections.count)",
                    text: r,
                    sourceDate: entry.date,
                    sourceEntryId: entry.id,
                    sourceEntryTitle: entry.title
                ))
            }
        }
        // Sort by date ascending (oldest first → newest) so the
        // reflection reads as a timeline.
        return reflections.sorted { $0.sourceDate < $1.sourceDate }
    }

    // MARK: - Sentence extraction

    /// Pick one sentence from `body` that's roughly
    /// `length`-shaped (12-80 chars in our case) and
    /// not too obviously a "header" line.
    private static func pickSentence(
        from body: String,
        entryVec: [Double],
        embedding: NLEmbedding,
        config: Config
    ) -> String? {
        // Naive split on sentence-ending Chinese punctuation. We
        // deliberately don't use NLTokenizer's sentence mode
        // here because Chinese sentence boundaries are tricky
        // and we want a single-line result.
        let separatorSet = CharacterSet(charactersIn: "。！？\n")
        let raw = body.components(separatedBy: separatorSet)
        let candidates: [String] = raw
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { s in
                let len = s.count
                return len >= config.minCharsPerSentence && len <= config.maxCharsPerSentence
            }
        guard let pick = candidates.randomElement() else { return nil }
        return stripMarkdown(pick)
    }

    // MARK: - Vector math

    private static func averageVector(
        for text: String,
        embedding: NLEmbedding
    ) -> [Double]? {
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            if let v = embedding.vector(for: token) {
                for i in 0..<sum.count {
                    sum[i] += v[i]
                }
                count += 1
            }
            return true
        }
        guard count > 0 else { return nil }
        let inv = 1.0 / Double(count)
        for i in 0..<sum.count {
            sum[i] *= inv
        }
        return l2Normalize(sum)
    }

    private static func centroid(of vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var sum = [Double](repeating: 0, count: first.count)
        for v in vectors {
            for i in 0..<sum.count {
                sum[i] += v[i]
            }
        }
        let inv = 1.0 / Double(vectors.count)
        for i in 0..<sum.count {
            sum[i] *= inv
        }
        return l2Normalize(sum)
    }

    private static func l2Normalize(_ v: [Double]) -> [Double] {
        var mag = 0.0
        for x in v { mag += x * x }
        mag = sqrt(mag)
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }

    private static func stripMarkdown(_ s: String) -> String {
        var t = s
        while t.hasPrefix("#") { t = String(t.dropFirst()); t = t.trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("> ") { t = String(t.dropFirst(2)) }
        if t.hasPrefix("- ") { t = String(t.dropFirst(2)) }
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Fallback

    /// When embedding isn't available (older macOS), fall back
    /// to picking random sentences from random entries. Less
    /// magical but still useful.
    private static func fallbackSample(
        from pool: [DiaryEntry],
        config: Config
    ) -> [MirrorReflection] {
        var picked: [(DiaryEntry, String)] = []
        let shuffled = pool.shuffled()
        for entry in shuffled {
            if picked.count >= config.outputCount { break }
            // Naive sentence pick.
            let candidates = entry.rawContent
                .components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= config.minCharsPerSentence && $0.count <= config.maxCharsPerSentence }
            if let s = candidates.randomElement() {
                picked.append((entry, stripMarkdown(s)))
            }
        }
        return picked.sorted { $0.0.date < $1.0.date }.enumerated().map { (i, pair) in
            MirrorReflection(
                id: "\(pair.0.id)#\(i)",
                text: pair.1,
                sourceDate: pair.0.date,
                sourceEntryId: pair.0.id,
                sourceEntryTitle: pair.0.title
            )
        }
    }
}
