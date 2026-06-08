import Foundation
import NaturalLanguage

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

    /// Frequent *content* words across all entries' bodies.
    ///
    /// Approach — leverage Apple's built-in tokenizer instead of hand-rolling
    /// a Chinese segmenter (which is what produced "那那种" / "一周人很" noise
    /// in the first iteration):
    ///   1. `NLTokenizer(.word)` — Apple's NaturalLanguage framework, ships
    ///      with macOS, handles Chinese / Japanese / Korean word boundaries
    ///      using internal heuristics. No external dependency, no bigram
    ///      mess. `.joinNames` keeps multi-character proper names together
    ///      (e.g. "Lily", "小赵").
    ///   2. Filter: drop anything in `stopwords`, anything < 2 chars, anything
    ///      that's purely digits or punctuation.
    ///   3. **Per-entry de-dup** + **cross-entry adaptive threshold**: a token
    ///      must appear in at least `max(2, ceil(0.2 * n))` different entries
    ///      to count. This is the only filter that needs to do real work
    ///      once `NLTokenizer` is producing real words.
    static func wordFrequency(
        entries: [DiaryEntry],
        maxResults: Int = 50,
        minEntries: Int = 2
    ) -> [(word: String, count: Int)] {
        var tokenCounts: [String: Int] = [:]
        var entryTokenSets: [Set<String>] = []
        entryTokenSets.reserveCapacity(entries.count)

        for e in entries {
            var seen = Set<String>()
            tokenize(e.plainText) { tok in
                if !seen.contains(tok) {
                    seen.insert(tok)
                    tokenCounts[tok, default: 0] += 1
                }
            }
            entryTokenSets.append(seen)
        }

        // Adaptive cross-entry threshold: at least 2 entries; for large
        // libraries, scale to ~20% so the cloud stays curated rather than
        // dumping every "今晚吃了 XX" 2-occurrence compound.
        let n = entries.count
        let adaptive = Int((Double(n) * 0.2).rounded(.up))
        let threshold = max(2, adaptive, minEntries)

        let filtered = tokenCounts.filter { token, _ in
            var cnt = 0
            for s in entryTokenSets where s.contains(token) {
                cnt += 1
                if cnt >= threshold { return true }
            }
            return false
        }

        return filtered
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(maxResults)
            .map { ($0.key, $0.value) }
    }

    /// Pass each token to the closure.
    ///
    /// Backed by `NLTokenizer(.word)` — Apple's built-in CJK-aware word
    /// segmenter. The previous hand-rolled 2-/3-gram sliding window produced
    /// 1-gram fragments (理, 意, 公) that don't look like real words; Apple's
    /// tokenizer splits Chinese into actual semantic units (焦虑, 数据看板,
    /// 回家, 收尾, 公里) without any external dependency.
    private static func tokenize(_ text: String, _ yield: (String) -> Void) {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let opts: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: opts
        ) { _, range in
            let raw = String(text[range])
            let tok = raw.lowercased()
            if tok.count >= 2
                && !stopwords.contains(tok)
                && tok.contains(where: { $0.isLetter }) {
                yield(tok)
            }
            return true
        }
    }

    /// Stopwords — kept minimal now that `NLTokenizer` produces real CJK
    /// words. Only filter obvious function words / hedges that would
    /// otherwise dominate the cloud at the cost of content words.
    /// Exposed as `internal` (default) so the embedding index can reuse
    /// the same set when tokenising diary text for semantic retrieval.
    static let stopwords: Set<String> = [
        // ----- Chinese function words / particles / pronouns -----
        "的", "了", "着", "过", "是", "在", "和", "也", "都", "还", "就",
        "但", "而", "把", "被", "让", "使", "由", "以", "及", "或", "且",
        "要", "有", "没", "不", "会", "能", "可", "该", "得",
        "我", "你", "他", "她", "它", "们", "自", "己",
        "这", "那", "哪", "之", "么",
        "吗", "吧", "呢", "啊", "哦", "嗯", "哎", "啦", "哈", "呀", "嘛",
        "啊", "哦", "嗯", "呀", "唉", "哎", "呵",
        "跟", "给", "对", "到", "从", "向",
        "很", "太", "极", "最", "挺", "确", "又", "再", "才", "已", "仍",
        "并", "倒", "候", "时",
        "的", "地", "得",
        // Time-of-day fillers — they show up in nearly every entry but
        // carry no thematic signal. Keep "凌晨/半夜" out: those are mood
        // signals worth surfacing.
        "今天", "昨天", "明天", "前天", "后天", "现在",
        "昨晚", "今晚", "早上", "上午", "中午", "下午", "晚上",
        "之前", "之后", "以前", "以后", "后来", "刚才", "刚刚",
        // Hedges / adverbs
        "有点", "一点", "一下", "一些", "一会", "一会儿",
        "可能", "也许", "大概", "或许", "一定", "应该",
        "真的", "确实", "其实", "当然", "不过", "然而",
        "因为", "所以", "但是", "如果", "虽然", "然后", "接着", "于是", "由于",
        "这种", "那种", "这种", "那个", "这个", "这些", "那些",
        "怎么", "什么", "为什么", "如何",
        // Common verbs (low information density in a diary)
        "觉得", "认为", "知道", "记得", "好像", "似乎", "发现", "考虑",
        "决定", "选择", "开始", "结束", "继续", "准备",
        "想", "说", "做", "走", "看", "听", "吃", "喝", "睡", "醒", "起",
        "坐", "站", "跑", "停", "回", "进", "出", "入", "来", "去",
        "拿", "放", "开", "关", "用", "买", "卖", "弄",
        "接", "近", "离",
        // Generic nouns
        "东西", "事情", "事儿", "话", "问题", "时候", "时间",
        "地方", "情况", "状态", "方式", "方法", "原因", "结果",
        "过程", "方面", "样子",
        "工作", "生活", "家", "公司", "学校", "世界",
        "我们", "你们", "他们", "她们", "它们", "自己",
        "朋友", "家人", "同事", "爸妈", "父母",
        // Common emoji-less punctuation fragments
        "这么", "那么", "这样", "那样", "这里", "那里", "这儿", "那儿",
        // ----- English stopwords -----
        "the", "a", "an", "and", "or", "but", "is", "are", "was", "were",
        "in", "on", "at", "to", "for", "of", "with", "by", "as", "from",
        "this", "that", "these", "those", "it", "its", "i", "you", "he", "she",
        "we", "they", "my", "your", "his", "her", "our", "their",
        "be", "been", "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "may", "might", "can",
        "not", "no", "yes", "ok", "okay", "yeah", "hmm"
    ]

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
