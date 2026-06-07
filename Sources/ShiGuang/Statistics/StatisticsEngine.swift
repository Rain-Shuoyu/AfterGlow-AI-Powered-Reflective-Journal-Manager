import Foundation

/// Pure functions that turn a list of `DiaryEntry` into `DiaryStats`.
enum StatisticsEngine {

    static func compute(entries: [DiaryEntry]) -> DiaryStats {
        guard !entries.isEmpty else { return .empty }

        let totalWords = entries.reduce(0) { $0 + $1.wordCount }
        let totalChars = entries.reduce(0) { $0 + $1.characterCount }
        let avg = Double(totalWords) / Double(entries.count)

        let sorted = entries.sorted { $0.date < $1.date }
        let start = sorted.first?.date
        let end = sorted.last?.date
        let range: (Date, Date)? = {
            guard let s = start, let e = end else { return nil }
            return (s, e)
        }()

        let (longest, current) = streaks(from: entries)
        let mood = moodDistribution(entries: entries)
        let tags = tagFrequency(entries: entries)
        let words = wordFrequency(entries: entries)
        let daily = dailyMetrics(entries: entries)
        let monthly = monthlyMetrics(daily: daily)

        return DiaryStats(
            totalEntries: entries.count,
            totalWords: totalWords,
            totalCharacters: totalChars,
            dateRange: range,
            averageWordsPerEntry: avg,
            writingStreakDays: longest,
            currentStreakDays: current,
            moodDistribution: mood,
            tagFrequency: tags,
            wordFrequency: words,
            dailyWordCounts: daily,
            monthlyWordCounts: monthly
        )
    }

    // MARK: - Streaks

    static func streaks(from entries: [DiaryEntry]) -> (longest: Int, current: Int) {
        guard !entries.isEmpty else { return (0, 0) }
        let cal = Calendar.current
        let dayKeys = Set(entries.map { cal.startOfDay(for: $0.date) })
        let sorted = dayKeys.sorted()

        // longest
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if let next = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               cal.isDate(next, inSameDayAs: sorted[i]) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        // current streak ending today (or yesterday — gap of 1 day allowed)
        let today = cal.startOfDay(for: Date())
        var current = 0
        var cursor = today
        if !dayKeys.contains(cursor) {
            // allow grace day
            if let yesterday = cal.date(byAdding: .day, value: -1, to: today), dayKeys.contains(yesterday) {
                cursor = yesterday
            } else {
                return (longest, 0)
            }
        }
        while dayKeys.contains(cursor) {
            current += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return (longest, current)
    }

    // MARK: - Mood distribution

    static func moodDistribution(entries: [DiaryEntry]) -> [MoodBucket] {
        var counts = [Int: Int]()
        for e in entries {
            if let m = e.frontmatter.mood {
                counts[m, default: 0] += 1
            } else if let label = e.frontmatter.moodLabel?.lowercased() {
                // soft label -> bucket 1..5
                let bucket: Int
                switch label {
                case "很差", "极差", "糟", "崩", "terrible", "awful": bucket = 1
                case "差", "低落", "难过", "sad", "bad", "low": bucket = 2
                case "一般", "还行", "ok", "okay", "meh": bucket = 3
                case "好", "不错", "开心", "happy", "good": bucket = 4
                case "很好", "超棒", "兴奋", "great", "amazing": bucket = 5
                default: bucket = 3
                }
                counts[bucket, default: 0] += 1
            }
        }
        let labels = ["", "很差", "差", "一般", "好", "很好"]
        return (1...5).map { MoodBucket(id: $0, label: labels[$0], count: counts[$0] ?? 0) }
    }

    // MARK: - Tags

    static func tagFrequency(entries: [DiaryEntry]) -> [(tag: String, count: Int)] {
        var freq: [String: Int] = [:]
        for e in entries {
            for t in e.frontmatter.tags {
                freq[t, default: 0] += 1
            }
        }
        return freq.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.map { ($0.key, $0.value) }
    }

    // MARK: - Word frequency (content)

    /// Frequent *content* words across all entries' bodies, minus a stopword
    /// set and capped at a sensible length so a long unpunctuated Chinese
    /// sentence doesn't get counted as a single mega-token.
    ///
    /// Tokenization:
    ///   - Latin runs → per-word (lowercased)
    ///   - CJK runs  → 1-gram per char + 2-gram (bigram) sliding window
    ///   - Either way: drop tokens longer than the cap (CJK 6, Latin 1 word)
    static func wordFrequency(
        entries: [DiaryEntry],
        maxResults: Int = 50
    ) -> [(word: String, count: Int)] {
        var freq: [String: Int] = [:]
        for e in entries {
            countWords(in: e.plainText, into: &freq)
        }
        return freq
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(maxResults)
            .map { ($0.key, $0.value) }
    }

    private static let stopwords: Set<String> = [
        // Chinese function words
        "的", "了", "是", "在", "我", "你", "他", "她", "它", "们",
        "这", "那", "这个", "那个", "和", "也", "都", "还", "就", "但",
        "要", "有", "没", "不", "吗", "吧", "呢", "啊", "哦", "嗯",
        "上", "下", "里", "外", "中", "前", "后", "内", "间", "边",
        "什么", "怎么", "为什么", "如何", "可以", "可能", "应该", "觉得",
        "今天", "昨天", "明天", "现在", "以前", "以后", "时候",
        "我们", "你们", "他们", "她们", "它们",
        "因为", "所以", "但是", "如果", "虽然", "然后", "接着", "于是",
        // English
        "the", "a", "an", "and", "or", "but", "is", "are", "was", "were",
        "in", "on", "at", "to", "for", "of", "with", "by", "as", "from",
        "this", "that", "these", "those", "it", "its", "i", "you", "he", "she",
        "we", "they", "my", "your", "his", "her", "our", "their",
        "be", "been", "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "may", "might", "can",
        "not", "no", "yes", "ok", "okay", "yeah", "hmm"
    ]

    private static func countWords(in text: String, into freq: inout [String: Int]) {
        // Tokenize per character scalar: build runs of CJK vs runs of "other".
        // - CJK run   → unigrams + bigrams (2-char windows)
        // - Other run → split on whitespace + punctuation, per-word
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "，。！？；：、（）「」『』《》…—"))

        // Build a "type per char" map: 0=skip, 1=CJK, 2=other
        var kinds: [Int] = []
        kinds.reserveCapacity(text.unicodeScalars.count)
        for s in text.unicodeScalars {
            if separators.contains(s) {
                kinds.append(0)
            } else if isCJK(s) {
                kinds.append(1)
            } else {
                kinds.append(2)
            }
        }

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            // Skip separators
            while i < chars.count && kinds[i] == 0 { i += 1 }
            if i >= chars.count { break }

            // Find run [start, end)
            let start = i
            let kind = kinds[i]
            while i < chars.count && kinds[i] == kind { i += 1 }
            let end = i
            let run = String(chars[start..<end])

            if kind == 1 {
                // CJK run: emit 1-grams and 2-grams
                let cjkChars = Array(run)
                // 1-gram: each character (skipping stopword single chars)
                for ch in cjkChars {
                    let s = String(ch)
                    if !stopwords.contains(s) {
                        freq[s, default: 0] += 1
                    }
                }
                // 2-gram: every adjacent pair
                if cjkChars.count >= 2 {
                    for j in 0..<(cjkChars.count - 1) {
                        let bigram = String(cjkChars[j...j+1])
                        // Skip bigrams that are entirely stopword chars
                        let a = String(cjkChars[j])
                        let b = String(cjkChars[j+1])
                        if stopwords.contains(a) && stopwords.contains(b) { continue }
                        freq[bigram, default: 0] += 1
                    }
                }
            } else {
                // Other run: per-word (lowercased), cap to single token
                for word in run.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) {
                    let lower = String(word).lowercased()
                    if lower.count >= 2 && !stopwords.contains(lower) {
                        freq[lower, default: 0] += 1
                    }
                }
            }
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x3040...0x309F).contains(v)
            || (0x30A0...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

    // MARK: - Daily / monthly metrics

    static func dailyMetrics(entries: [DiaryEntry]) -> [DailyMetric] {
        let cal = Calendar.current
        var bucket: [Date: (words: Int, count: Int, moodSum: Int, moodN: Int)] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.date)
            var cur = bucket[day] ?? (0, 0, 0, 0)
            cur.words += e.wordCount
            cur.count += 1
            if let m = e.frontmatter.mood {
                cur.moodSum += m
                cur.moodN += 1
            }
            bucket[day] = cur
        }
        return bucket
            .map { day, v in
                DailyMetric(
                    date: day,
                    wordCount: v.words,
                    entryCount: v.count,
                    mood: v.moodN > 0 ? Int((Double(v.moodSum) / Double(v.moodN)).rounded()) : nil
                )
            }
            .sorted { $0.date < $1.date }
    }

    static func monthlyMetrics(daily: [DailyMetric]) -> [MonthlyMetric] {
        let cal = Calendar.current
        var bucket: [String: (year: Int, month: Int, words: Int, count: Int, moodSum: Int, moodN: Int)] = [:]
        for d in daily {
            let comps = cal.dateComponents([.year, .month], from: d.date)
            guard let y = comps.year, let m = comps.month else { continue }
            let key = "\(y)-\(m)"
            var cur = bucket[key] ?? (y, m, 0, 0, 0, 0)
            cur.words += d.wordCount
            cur.count += d.entryCount
            if let mood = d.mood {
                cur.moodSum += mood
                cur.moodN += 1
            }
            bucket[key] = cur
        }
        return bucket.values
            .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
            .map { v in
                MonthlyMetric(
                    year: v.year,
                    month: v.month,
                    wordCount: v.words,
                    entryCount: v.count,
                    averageMood: v.moodN > 0 ? Double(v.moodSum) / Double(v.moodN) : nil
                )
            }
    }
}
