import Foundation

/// "🕯 周年回响" — match a diary entry to "this day, N years ago".
///
/// The matching rule is intentionally **loose**:
///   - day + month must match today's day + month
///   - year must differ
///
/// We do NOT do strict "exactly 365 days ago" because:
///   - the user's year of writing may not be contiguous
///   - leap years off-by-one would silently miss matches
///   - 6/15 ± 1 day feels more natural for a "today" anchor
struct AnniversaryEntry: Identifiable, Hashable {
    let id: String                  // source DiaryEntry.id
    let entry: DiaryEntry
    let yearsAgo: Int               // 1, 2, 3, ...
    let preview: String             // first 2-3 paragraphs of the body
}

enum AnniversaryFinder {

    /// Maximum number of years we'll surface. Older entries get
    /// collapsed to a "more from +N years ago" hint.
    static let maxYearsBack = 5

    /// Find anniversary entries for a given day. Returns at most
    /// `maxYearsBack` results, sorted newest-year first (1 year
    /// ago first, then 2 years, then 3, etc.).
    ///
    /// The set of returned entries tells the user "this date has
    /// been on your calendar for N years" — even if not every
    /// year is represented (e.g. 1 year ago missing, 2 years ago
    /// present, 3 years ago present).
    static func find(in entries: [DiaryEntry], for date: Date = Date()) -> [AnniversaryEntry] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let todayYear = comps.year,
              let todayMonth = comps.month,
              let todayDay = comps.day
        else { return [] }

        // For each entry, compute yearsAgo and filter to same m/d
        // in a different year.
        var matches: [AnniversaryEntry] = []
        for e in entries {
            let eComps = cal.dateComponents([.year, .month, .day], from: e.date)
            guard let eYear = eComps.year,
                  let eMonth = eComps.month,
                  let eDay = eComps.day
            else { continue }
            if eMonth != todayMonth || eDay != todayDay { continue }
            let yearsAgo = todayYear - eYear
            if yearsAgo <= 0 { continue }      // not the same year (or future)
            if yearsAgo > maxYearsBack { continue }
            let preview = makePreview(from: e.rawContent, maxParagraphs: 3)
            matches.append(AnniversaryEntry(
                id: e.id,
                entry: e,
                yearsAgo: yearsAgo,
                preview: preview
            ))
        }
        // Sort: most recent year first.
        return matches.sorted { $0.yearsAgo < $1.yearsAgo }
    }

    /// Is `date` inside the "anniversary window" (today ± 1 day)?
    /// Used to decide whether to show the banner on app launch.
    static func isInAnniversaryWindow(_ date: Date = Date()) -> Bool {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: date),
              let tomorrow = cal.date(byAdding: .day, value: 1, to: date)
        else { return false }
        // We only need to check whether *this specific day* falls
        // in the window — not whether today matches an entry.
        // The caller (banner logic) handles the matching.
        return cal.isDateInYesterday(date) == false
            && cal.isDateInTomorrow(date) == false
            ? true
            : cal.isDateInYesterday(yesterday)
                || cal.isDateInTomorrow(tomorrow)
                || cal.isDateInToday(date)
    }

    // MARK: - Preview

    /// Take the first `maxParagraphs` non-empty paragraphs of a
    /// markdown body and turn them into a plain-text preview.
    /// Strips leading markdown headers / blockquote markers so
    /// the preview reads naturally.
    private static func makePreview(from raw: String, maxParagraphs: Int) -> String {
        // Split on double-newline paragraph boundaries.
        let paragraphs = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let head = paragraphs.prefix(maxParagraphs)
        let cleaned = head.map { stripMarkdownMarkers($0) }
        let joined = cleaned.joined(separator: "\n\n")
        // Cap at ~300 chars total so the sheet doesn't get
        // overwhelmed.
        if joined.count <= 300 { return joined }
        let endIdx = joined.index(joined.startIndex, offsetBy: 300)
        return String(joined[..<endIdx]) + "…"
    }

    private static func stripMarkdownMarkers(_ s: String) -> String {
        var t = s
        // Remove leading headers: ### / ## / #
        while t.hasPrefix("#") {
            t = String(t.dropFirst())
            t = t.trimmingCharacters(in: .whitespaces)
        }
        // Remove blockquote marker
        if t.hasPrefix("> ") {
            t = String(t.dropFirst(2))
        }
        // Remove leading list markers
        for marker in ["- ", "* ", "+ "] {
            if t.hasPrefix(marker) {
                t = String(t.dropFirst(marker.count))
                break
            }
        }
        // Remove bold/italic markers (they're not visible in the
        // preview anyway, but they take up characters).
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }
}
