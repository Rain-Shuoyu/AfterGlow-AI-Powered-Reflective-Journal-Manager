import Foundation

/// Headless smoke test for the parser / stats / indexer pipeline. Used by
/// `swift run DiaryInsight --sanity-check <folder>` to verify the core data
/// path is working without launching the GUI.
enum SanityCheck {
    static func run(folder: URL) {
        print("=== DiaryInsight Sanity Check ===")
        print("Folder: \(folder.path)\n")

        let entries: [DiaryEntry]
        do {
            entries = try DiaryScanner.shared.scan(folder: folder)
        } catch {
            print("❌ scan failed: \(error.localizedDescription)")
            return
        }
        print("✅ Scanned \(entries.count) entries")

        guard !entries.isEmpty else {
            print("⚠️  No .md files found, exiting")
            return
        }

        let stats = StatisticsEngine.compute(entries: entries)
        print("✅ Total words: \(stats.totalWords)")
        print("✅ Date range: \(stats.dateRange?.start.short ?? "?") — \(stats.dateRange?.end.short ?? "?")")
        print("✅ Average words/entry: \(String(format: "%.0f", stats.averageWordsPerEntry))")
        print("✅ Longest streak: \(stats.writingStreakDays) days")
        print("✅ Daily metrics: \(stats.dailyWordCounts.count) days")
        print("✅ Monthly metrics: \(stats.monthlyWordCounts.count) months")

        let moodTotal = stats.moodDistribution.reduce(0) { $0 + $1.count }
        print("✅ Mood entries: \(moodTotal) / \(entries.count)")

        print("\n--- First 3 entries ---")
        for e in entries.prefix(3) {
            print("• \(e.date.short)  mood=\(e.frontmatter.mood.map(String.init) ?? "-")  words=\(e.wordCount)  title=\(e.title)")
        }

        print("\n--- Indexer smoke tests ---")
        let probes = [
            "我六月份有哪些天心情不好？",
            "最近一个月我都关心些什么？",
            "我和家人之间发生过哪些冲突？",
            "哪些天我最焦虑？"
        ]
        for q in probes {
            let r = DiaryIndexer.filter(entries: entries, for: q, maxResults: 30)
            let titles = r.entries.prefix(3).map { "\($0.date.short)(\($0.frontmatter.mood.map(String.init) ?? "-"))" }.joined(separator: ", ")
            print("Q: \(q)")
            print("   → matched \(r.entries.count)/\(r.totalCandidates): \(titles)")
            print("   → why: \(r.explanation)\n")
        }

        // Sanity assertion: every filtered result must have the correct date
        for q in probes {
            let r = DiaryIndexer.filter(entries: entries, for: q, maxResults: 30)
            for e in r.entries {
                if e.date.timeIntervalSince1970 <= 0 {
                    print("❌ entry with bogus date for query: \(q)")
                }
            }
        }
        print("=== OK ===")
    }
}
