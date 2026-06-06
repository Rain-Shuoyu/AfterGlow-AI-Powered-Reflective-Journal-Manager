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
