import Foundation

// MARK: - Diary Entry

/// A single diary entry parsed from one markdown file.
struct DiaryEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String              // stable id, derived from path
    let url: URL                // file URL on disk
    let date: Date              // the date this entry represents (from frontmatter `date:` or filename)
    let title: String           // frontmatter `title:` or first heading or filename
    let rawContent: String      // raw markdown body (after frontmatter stripped)
    let frontmatter: Frontmatter
    let wordCount: Int
    let characterCount: Int
    let createdAt: Date?        // file creation date (best effort)
    let modifiedAt: Date?       // file modification date

    /// Convenience: the first ~200 chars of content, used for previews.
    var preview: String {
        let trimmed = rawContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 200 { return trimmed }
        return String(trimmed.prefix(200)) + "…"
    }

    /// Plain-text body (markdown stripped of basic syntax). Used when sending to LLMs.
    var plainText: String {
        DiaryEntry.markdownToPlainText(rawContent)
    }
}

// MARK: - Frontmatter

/// Loose YAML frontmatter parser. Supports the small set of keys we actually use;
/// anything else is kept as `extra` for round-tripping.
struct Frontmatter: Hashable, Codable, Sendable {
    var mood: Int?              // 1-5 scale, optional
    var moodLabel: String?      // free-form label, e.g. "低落", "焦虑"
    var weather: String?
    var tags: [String]
    var title: String?
    var date: Date?             // explicit date in frontmatter overrides filename
    var extra: [String: String] // unknown keys preserved

    static let empty = Frontmatter(mood: nil, moodLabel: nil, weather: nil, tags: [], title: nil, date: nil, extra: [:])
}

// MARK: - Statistics

struct DiaryStats {
    let totalEntries: Int
    let totalWords: Int
    let totalCharacters: Int
    let dateRange: (start: Date, end: Date)?
    let averageWordsPerEntry: Double
    let writingStreakDays: Int           // longest consecutive-day streak with at least one entry
    let currentStreakDays: Int           // current consecutive-day streak ending today
    let moodDistribution: [MoodBucket]   // histogram
    let tagFrequency: [(tag: String, count: Int)]
    let dailyWordCounts: [DailyMetric]   // for heatmap + trend chart
    let monthlyWordCounts: [MonthlyMetric]

    static let empty = DiaryStats(
        totalEntries: 0,
        totalWords: 0,
        totalCharacters: 0,
        dateRange: nil,
        averageWordsPerEntry: 0,
        writingStreakDays: 0,
        currentStreakDays: 0,
        moodDistribution: [],
        tagFrequency: [],
        dailyWordCounts: [],
        monthlyWordCounts: []
    )
}

struct MoodBucket: Identifiable, Hashable {
    let id: Int        // 1...5
    let label: String  // "很差" / "差" / "一般" / "好" / "很好"
    let count: Int
}

struct DailyMetric: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let wordCount: Int
    let entryCount: Int
    let mood: Int?     // average mood (1-5) for the day, if any entry declared a mood
}

struct MonthlyMetric: Identifiable, Hashable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int     // 1...12
    let wordCount: Int
    let entryCount: Int
    let averageMood: Double?
}

// MARK: - Markdown helpers

extension DiaryEntry {
    /// Very small markdown-to-plain-text converter. Strips headings, emphasis, code fences,
    /// links (keeps link text), images, blockquotes, list markers. Good enough for LLM input.
    static func markdownToPlainText(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var inCodeFence = false
        var out: [String] = []

        for raw in lines {
            let line = raw

            // Fenced code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }

            // Headings
            var stripped = line
            if let _ = stripped.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                stripped = stripped.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            }

            // Blockquote markers
            stripped = stripped.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)

            // List markers
            stripped = stripped.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            stripped = stripped.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)

            // Images: ![alt](url) -> alt
            stripped = stripped.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)

            // Links: [text](url) -> text
            stripped = stripped.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)

            // Inline code `x`
            stripped = stripped.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)

            // Bold/italic markers
            stripped = stripped.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            stripped = stripped.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
            stripped = stripped.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            stripped = stripped.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)

            // HTML tags
            stripped = stripped.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

            out.append(stripped)
        }
        return out.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
