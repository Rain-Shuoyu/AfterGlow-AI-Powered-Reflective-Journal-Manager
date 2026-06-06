import Foundation

/// Lightweight, in-memory "retrieval" layer for diary entries.
///
/// We deliberately avoid a vector DB — the diary is small, queries are typically
/// time-bounded ("六月", "上周", "和家人吵架"), and we want to keep the app
/// fully local. This filter handles:
///   - Chinese + English month keywords ("六月" / "June")
///   - Year keywords ("2024", "去年")
///   - Week / day / range phrases
///   - Mood keywords ("心情不好", "焦虑", "开心")
///   - Free-form keyword fallback (substring match in title / tags / content)
struct DiaryQuery {
    var rawQuestion: String
}

struct DiaryFilterResult {
    var entries: [DiaryEntry]   // filtered, ordered by date desc
    var explanation: String     // human-readable summary of what we matched
    var totalCandidates: Int    // size of the full index when this was computed
}

enum DiaryIndexer {

    static func filter(entries: [DiaryEntry], for question: String, maxResults: Int = 30) -> DiaryFilterResult {
        let q = question.lowercased()
        var why: [String] = []

        // 1. Mood-based filtering
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
        for t in moodTerms {
            if q.contains(t.label) {
                if t.wantBad { wantBad = true }
                if t.wantGood { wantGood = true }
                why.append("情绪关键词「\(t.label)」")
            }
        }

        // 2. Time filtering
        let now = Date()
        let cal = Calendar.current
        var dateRange: ClosedRange<Date>?
        var rangeLabel = ""

        // explicit "YYYY年MM月" or "MM月"
        if let (year, month) = parseYearMonth(q) {
            if let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
               let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) {
                let dayEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end
                dateRange = start...dayEnd
                rangeLabel = "\(year)年\(month)月"
                why.append("时间范围：\(rangeLabel)")
            }
        } else if let month = parseMonthName(q) {
            // bare month name in current year
            let comps = cal.dateComponents([.year], from: now)
            if let year = comps.year, let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
               let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) {
                let dayEnd = cal.date(byAdding: .day, value: 1, to: end) ?? end
                dateRange = start...dayEnd
                rangeLabel = "\(year)年\(month)月"
                why.append("时间范围：\(rangeLabel)")
            }
        } else if q.contains("上周") || q.contains("last week") {
            if let lastWeekStart = cal.date(byAdding: .day, value: -13, to: now),
               let lastWeekEnd = cal.date(byAdding: .day, value: -7, to: now) {
                let s = cal.startOfDay(for: lastWeekStart)
                let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastWeekEnd)) ?? lastWeekEnd
                dateRange = s...e
                rangeLabel = "上周"
                why.append("时间范围：上周")
            }
        } else if q.contains("这周") || q.contains("本周") || q.contains("this week") {
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start {
                let s = cal.startOfDay(for: weekStart)
                let e = cal.date(byAdding: .day, value: 1, to: now) ?? now
                dateRange = s...e
                rangeLabel = "本周"
                why.append("时间范围：本周")
            }
        } else if q.contains("最近") || q.contains("latest") || q.contains("recent") {
            let s = cal.date(byAdding: .day, value: -30, to: now) ?? now
            dateRange = s...now
            rangeLabel = "最近30天"
            why.append("时间范围：最近30天")
        } else if q.contains("去年") || q.contains("last year") {
            let comps = cal.dateComponents([.year], from: now)
            let currentYear = comps.year ?? Calendar.current.component(.year, from: now)
            let year = currentYear - 1
            if let s = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
               let e = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
                dateRange = s...e
                rangeLabel = "\(year)年"
                why.append("时间范围：\(year)年")
            }
        } else if let year = parseYear(q) {
            if let s = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
               let e = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
                dateRange = s...e
                rangeLabel = "\(year)年"
                why.append("时间范围：\(year)年")
            }
        }

        // 3. Free-text keywords (strip very common stopwords + the chinese numerals we used)
        let stopwords: Set<String> = [
            "的", "了", "是", "我", "你", "他", "她", "它", "我们", "你們", "的話",
            "吗", "呢", "啊", "吧", "嘛", "哈", "哦",
            "what", "which", "when", "where", "who", "do", "does", "did",
            "is", "are", "was", "were", "the", "a", "an", "and", "or",
            "有", "哪些", "什么", "怎么", "为什么", "哪些天", "哪天", "那些", "这个", "那个"
        ]
        // 3-char chunks + single Chinese chars (naive)
        var keywords: [String] = []
        let cleaned = q.replacingOccurrences(of: #"[，。！？、,!?.;:]"#, with: " ", options: .regularExpression)
        for token in cleaned.split(whereSeparator: { $0.isWhitespace }) {
            let t = String(token)
            if t.count >= 2 && !stopwords.contains(t) { keywords.append(t) }
        }
        for ch in cleaned {
            if let scalar = ch.unicodeScalars.first,
               scalar.value >= 0x4E00, scalar.value <= 0x9FFF,  // CJK
               !stopwords.contains(String(ch)) {
                keywords.append(String(ch))
            }
        }
        // de-dupe, keep order
        var seen = Set<String>()
        keywords = keywords.filter { seen.insert($0).inserted }

        // 4. Apply filters
        var candidates = entries
        if let r = dateRange {
            candidates = candidates.filter { r.contains($0.date) }
        }
        if wantBad {
            candidates = candidates.filter { ($0.frontmatter.mood ?? 3) <= 2 }
        } else if wantGood {
            candidates = candidates.filter { ($0.frontmatter.mood ?? 3) >= 4 }
        }

        // keyword filter (OR semantics, plus title/tag/date bonus)
        let keywordFiltered: [DiaryEntry]
        if !keywords.isEmpty {
            keywordFiltered = candidates.filter { e in
                let hay = (e.title + " " + e.plainText + " " + e.frontmatter.tags.joined(separator: " ")).lowercased()
                return keywords.contains { hay.contains($0) }
            }
            // If keyword filter would return zero rows, fall back to the time/range candidates
            // (we still want to send the LLM the right window)
            if !keywordFiltered.isEmpty {
                candidates = keywordFiltered
                why.append("关键词：\(keywords.prefix(5).joined(separator: ", "))")
            } else {
                why.append("（关键词无精确匹配，按时间范围兜底）")
            }
        }

        if dateRange == nil && !wantBad && !wantGood && keywords.isEmpty {
            // open question -> return most recent N
            candidates = Array(entries.prefix(maxResults))
            why.append("未识别时间/情绪/关键词，取最近 \(maxResults) 篇")
        }

        let limited = Array(candidates.prefix(maxResults))
        let explanation = why.isEmpty ? "已匹配全部" : why.joined(separator: "；")
        return DiaryFilterResult(entries: limited, explanation: explanation, totalCandidates: entries.count)
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
