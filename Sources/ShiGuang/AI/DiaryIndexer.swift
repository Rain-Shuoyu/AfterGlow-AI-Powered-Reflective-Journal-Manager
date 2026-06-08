import Foundation
import NaturalLanguage

/// Two-stage retrieval for diary entries:
///
/// 1. **Pre-filter** (cheap, deterministic, user-controlled):
///    - Time phrases: "六月", "上周", "2024", "去年"
///    - Mood keywords: "焦虑", "开心", "崩溃"
///    - These narrow the candidate set so the LLM only sees the
///      *relevant window* of the diary.
///
/// 2. **Semantic rank** (cosine similarity over Apple's NLEmbedding):
///    - Tokenise each entry with `NLTokenizer` (CJK-aware, same as stats).
///    - Average the per-token word vectors from
///      `NLEmbedding.wordEmbedding(for: .simplifiedChinese)`.
///    - L2-normalise, then dot product == cosine.
///    - Cache to `~/Library/Application Support/ShiGuang/embeddings.json`,
///      invalidated by a content hash.
///
/// Falls back to the old keyword-sort path if NLEmbedding is unavailable
/// (very old macOS) or the query has no in-vocabulary token.
struct DiaryQuery {
    var rawQuestion: String
}

struct DiaryFilterResult {
    var entries: [DiaryEntry]   // ranked: time/mood window + semantic top-K
    var explanation: String     // human-readable summary of what we matched
    var totalCandidates: Int    // size of the full index when this was computed
}

enum DiaryIndexer {

    static func filter(entries: [DiaryEntry], for question: String, maxResults: Int = 30) -> DiaryFilterResult {
        let q = question.lowercased()
        var why: [String] = []
        let index = EmbeddingIndex.shared

        // ── 1. Pre-filter: mood ────────────────────────────────────────
        let moodTerms: [(label: String, wantBad: Bool, wantGood: Bool)] = [
            ("心情不好", true, false),
            ("不开心", true, false),
            ("难过", true, false),
            ("低落", true, false),
            ("焦虑", true, false),
            ("沮丧", true, false),
            ("崩溃", true, false),
            ("开心", false, true),
            ("快乐", false, true),
            ("兴奋", false, true),
            ("满足", false, true)
        ]
        var wantBad = false
        var wantGood = false
        for t in moodTerms where q.contains(t.label) {
            if t.wantBad { wantBad = true }
            if t.wantGood { wantGood = true }
            why.append("情绪关键词「\(t.label)」")
        }

        // ── 2. Pre-filter: time ────────────────────────────────────────
        let (dateRange, rangeLabel) = parseTimeRange(q, why: &why)
        if dateRange != nil {
            why.append("时间范围：\(rangeLabel)")
        }

        // ── 3. Build candidate set ─────────────────────────────────────
        var candidates = entries
        if let r = dateRange {
            candidates = candidates.filter { r.contains($0.date) }
        }
        if wantBad {
            candidates = candidates.filter { ($0.frontmatter.mood ?? 3) <= 2 }
        } else if wantGood {
            candidates = candidates.filter { ($0.frontmatter.mood ?? 3) >= 4 }
        }

        // ── 4. Semantic rank ───────────────────────────────────────────
        // Only enabled if NLEmbedding is on this Mac. Otherwise fall
        // through to the date-desc ordering.
        if index.isAvailable,
           let queryVec = index.embed(question) {
            var scored: [(DiaryEntry, Double)] = []
            scored.reserveCapacity(candidates.count)
            for entry in candidates {
                if let v = index.embeddingForEntry(entry) {
                    scored.append((entry, index.similarity(queryVec, v)))
                } else {
                    // Entry has no in-vocabulary tokens (e.g. emoji / numbers
                    // only). Push it to the bottom with a tiny negative
                    // score so the date filter still wins.
                    scored.append((entry, -1.0))
                }
            }
            scored.sort { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.date > rhs.0.date  // tie-break: newer first
            }
            candidates = scored.map { $0.0 }
            why.append("向量相似度排序")
            // Persist any new embeddings computed during this query.
            // (Non-blocking; the next saveCache from a write also flushes.)
            index.saveCache()
        }

        // ── 5. Open question fallback ──────────────────────────────────
        if dateRange == nil && !wantBad && !wantGood {
            // No time/mood signal — the vector rank alone decides.
            // If vector rank is also unavailable, the candidates are
            // already date-sorted (DiaryStore gives them in date desc).
            if !index.isAvailable {
                why.append("无 NLEmbedding，按日期降序")
            }
        }

        let limited = Array(candidates.prefix(maxResults))
        let explanation = why.isEmpty ? "已匹配全部" : why.joined(separator: "；")
        return DiaryFilterResult(entries: limited, explanation: explanation, totalCandidates: entries.count)
    }

    // MARK: - Time range parsing
    //
    // Extracted into a small helper so the main filter body stays focused
    // on the retrieval pipeline. Returns (range, label) — label is set
    // even when range is nil, but only appended to `why` at the call site
    // when non-nil.

    private static func parseTimeRange(_ q: String, why: inout [String]) -> (ClosedRange<Date>?, String) {
        let now = Date()
        let cal = Calendar.current

        if let (year, month) = parseYearMonth(q) {
            if let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
               let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) {
                let dayEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end
                return (start...dayEnd, "\(year)年\(month)月")
            }
        }
        if let month = parseMonthName(q) {
            if let year = cal.dateComponents([.year], from: now).year,
               let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
               let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) {
                let dayEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end
                return (start...dayEnd, "\(year)年\(month)月")
            }
        }
        if q.contains("上周") || q.contains("last week") {
            if let s = cal.date(byAdding: .day, value: -13, to: now),
               let e = cal.date(byAdding: .day, value: -7, to: now) {
                let ss = cal.startOfDay(for: s)
                let ee = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e)) ?? e
                return (ss...ee, "上周")
            }
        }
        if q.contains("这周") || q.contains("本周") || q.contains("this week") {
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start {
                let s = cal.startOfDay(for: weekStart)
                let e = cal.date(byAdding: .day, value: 1, to: now) ?? now
                return (s...e, "本周")
            }
        }
        if q.contains("最近") || q.contains("latest") || q.contains("recent") {
            let s = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return (s...now, "最近30天")
        }
        if q.contains("去年") || q.contains("last year") {
            let currentYear = cal.dateComponents([.year], from: now).year
                ?? cal.component(.year, from: now)
            let year = currentYear - 1
            if let s = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
               let e = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
                return (s...e, "\(year)年")
            }
        }
        if let year = parseYear(q) {
            if let s = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
               let e = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
                return (s...e, "\(year)年")
            }
        }
        return (nil, "")
    }

    // MARK: - Time parsing helpers

    static func parseYearMonth(_ q: String) -> (Int, Int)? {
        // "2024年6月" / "2024-06" / "2024/06"
        let patterns = [
            #"(\d{4})[\-./年](\d{1,2})"#,
            #"(\d{4})年(\d{1,2})月?"#
        ]
        for p in patterns {
            if let r = q.range(of: p, options: .regularExpression) {
                let s = String(q[r])
                let digits = s.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
                    .filter { !$0.isEmpty }
                if digits.count >= 2,
                   let y = Int(digits[0]),
                   let m = Int(digits[1]),
                   (1...12).contains(m) {
                    return (y, m)
                }
            }
        }
        return nil
    }

    static func parseYear(_ q: String) -> Int? {
        if let r = q.range(of: #"\b(20\d{2})\b"#, options: .regularExpression) {
            return Int(String(q[r]))
        }
        return nil
    }

    static func parseMonthName(_ q: String) -> Int? {
        let names: [(String, Int)] = [
            ("january", 1), ("jan", 1), ("february", 2), ("feb", 2),
            ("march", 3), ("mar", 3), ("april", 4), ("apr", 4),
            ("may", 5), ("june", 6), ("jun", 6),
            ("july", 7), ("jul", 7), ("august", 8), ("aug", 8),
            ("september", 9), ("sep", 9), ("sept", 9),
            ("october", 10), ("oct", 10), ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12)
        ]
        for (n, m) in names {
            if q.contains(n) { return m }
        }
        return nil
    }
}
