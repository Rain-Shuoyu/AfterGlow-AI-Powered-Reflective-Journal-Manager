import Foundation
import SwiftUI

/// "🌧 情绪急救" detector — should the rescue banner appear?
///
/// Two trigger paths:
///   1. **Numeric signal**: 3+ consecutive days with `mood_quick`
///      score ≤ 2 (i.e. 😔 or 😐), OR with `frontmatter.mood`
///      ≤ 2 on 3+ consecutive days.
///   2. **Keyword signal**: any of the past 7 days' free text
///      contains a distress keyword from `triggerKeywords`.
///
/// We intentionally keep both signals loose and require the
/// 3-day minimum so we don't pester users on a single bad day.
/// (One bad day is just life. Three bad days is something to
/// surface.)
struct RescueSignal: Hashable {
    let level: Level
    let daysAffected: Int
    let sampleText: String         // the most recent "mood_quick" text

    enum Level: Int, Hashable {
        case none        = 0
        case watch       = 1    // 3 days of low mood, but no keywords
        case intervene   = 2    // 3 days + distress keyword
    }
}

enum RescueDetector {

    /// Words that suggest the user might be in real distress.
    /// These are intentionally narrow and conservative — we
    /// only want to surface rescue content when the user has
    /// hinted at it themselves, not guess.
    ///
    /// Cultural context: in Chinese-speaking communities, people
    /// often understate their feelings ("还好", "撑得住", "没
    /// 事"). The keywords below are calibrated to catch both
    /// direct and indirect expression.
    static let triggerKeywords: [String] = [
        // direct distress
        "撑不住", "撑不下去了", "想死", "想消失", "没意义",
        "崩溃", "扛不住", "受不了", "熬不下去",
        // indirect but heavy
        "没用", "没人在乎", "没人关心", "我好累", "好累啊",
        "什么都不想做", "放弃",
        // self-criticism spirals
        "都是我不好", "我有问题", "我是不是",
    ]

    /// Inspect the past N days of diary entries and return a
    /// rescue signal. `entries` may be in any order — the
    /// detector will sort by date.
    static func detect(in entries: [DiaryEntry], today: Date = Date()) -> RescueSignal {
        let cal = Calendar.current
        let lookbackDays = 14

        // Build a m/d → entry map for the past N days.
        var dayMap: [Date: DiaryEntry] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.date)
            if let cutoff = cal.date(byAdding: .day, value: -lookbackDays, to: today),
               day >= cutoff && day <= today {
                dayMap[day] = e
            }
        }
        // Build the recent contiguous-day chain ending today.
        // Stop at the first missing day (a 3-day streak has to
        // be CONTIGUOUS).
        var chain: [DiaryEntry] = []
        var cursor = cal.startOfDay(for: today)
        for _ in 0..<lookbackDays {
            if let e = dayMap[cursor] {
                chain.append(e)
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }

        // Score each day: prefer mood_quick (more reliable, lower
        // stakes, set by the user just now), fall back to
        // frontmatter.mood.
        var scores: [(date: Date, score: Int, text: String)] = []
        for e in chain.reversed() {   // chronological
            let moodQuick = parseMoodQuick(from: e)
            let score: Int
            let text: String
            if let mq = moodQuick {
                score = mq.score
                text = "\(mq.emoji) \(mq.text)"
            } else if let m = e.frontmatter.mood {
                score = m
                text = "mood=\(m)"
            } else {
                continue    // skip days with no signal
            }
            scores.append((e.date, score, text))
        }

        // Find the longest trailing run of score ≤ 2.
        var run = 0
        for (_, s, _) in scores {
            if s <= 2 { run += 1 } else { break }
        }

        // Check for keyword hits in the past 7 days of text.
        var keywordHit: String? = nil
        let sevenDayCutoff = cal.date(byAdding: .day, value: -7, to: today) ?? today
        for (d, _, text) in scores where d >= sevenDayCutoff {
            for kw in triggerKeywords where text.contains(kw) {
                keywordHit = kw
                break
            }
            if keywordHit != nil { break }
        }

        // Decide level.
        if run >= 3 {
            if keywordHit != nil {
                return RescueSignal(
                    level: .intervene,
                    daysAffected: run,
                    sampleText: scores.first?.text ?? ""
                )
            }
            return RescueSignal(
                level: .watch,
                daysAffected: run,
                sampleText: scores.first?.text ?? ""
            )
        }
        return RescueSignal(level: .none, daysAffected: 0, sampleText: "")
    }

    /// Parse `mood_quick: "😔 撑了一天"` frontmatter format back
    /// into a `MoodQuick` struct. Returns nil if the field is
    /// missing or malformed.
    static func parseMoodQuick(from entry: DiaryEntry) -> MoodQuick? {
        guard let raw = entry.frontmatter.extra["mood_quick"]
              ?? entry.frontmatter.extra["moodQuick"]
        else { return nil }
        // The format is `<emoji> <text>`, e.g. `"😔 撑了一天"`.
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first,
              MoodQuick.allowedEmojis.contains(String(first))
        else { return nil }
        let emoji = String(first)
        let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        return MoodQuick(emoji: emoji, text: String(text))
    }
}

// MARK: - Store

@MainActor
final class RescueStore: ObservableObject {
    private static let lastShownKey = "DiaryInsight.Rescue.lastShownDate"
    private static let disabledKey  = "DiaryInsight.Rescue.userDisabled"
    private static let dismissedDatesKey = "DiaryInsight.Rescue.dismissedDates"
    private static let permanentDismissCountKey = "DiaryInsight.Rescue.permanentDismissCount"

    @Published private(set) var isUserDisabled: Bool
    @Published private(set) var lastShownDate: Date?
    @Published private(set) var dismissedDates: [String]
    /// Number of times the user has tapped "我不想再看到这个"。
    /// When this hits 5, we auto-disable.
    @Published private(set) var permanentDismissCount: Int

    init() {
        let d = UserDefaults.standard
        self.isUserDisabled = d.bool(forKey: Self.disabledKey)
        self.lastShownDate = d.object(forKey: Self.lastShownKey) as? Date
        self.dismissedDates = d.stringArray(forKey: Self.dismissedDatesKey) ?? []
        self.permanentDismissCount = d.object(forKey: Self.permanentDismissCountKey) as? Int ?? 0
    }

    /// Should the rescue banner appear right now? Pure function
    /// of the entries + cooldown state.
    func shouldShowBanner(entries: [DiaryEntry], today: Date = Date()) -> Bool {
        if isUserDisabled { return false }
        let signal = RescueDetector.detect(in: entries, today: today)
        guard signal.level != .none else { return false }
        if let last = lastShownDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 999
            if days < 7 { return false }
        }
        let key = Self.dateKey(today)
        if dismissedDates.contains(key) { return false }
        return true
    }

    /// Most-recent signal — used by the banner to pick wording.
    func currentSignal(entries: [DiaryEntry], today: Date = Date()) -> RescueSignal {
        RescueDetector.detect(in: entries, today: today)
    }

    func markShown(today: Date = Date()) {
        lastShownDate = today
        UserDefaults.standard.set(today, forKey: Self.lastShownKey)
    }

    func dismissForToday(today: Date = Date()) {
        let key = Self.dateKey(today)
        if !dismissedDates.contains(key) {
            dismissedDates.append(key)
            UserDefaults.standard.set(dismissedDates, forKey: Self.dismissedDatesKey)
        }
    }

    /// User said "我不想再看到这个" — increment the
    /// counter and auto-disable at 5.
    func permanentDismiss(today: Date = Date()) {
        permanentDismissCount += 1
        UserDefaults.standard.set(permanentDismissCount, forKey: Self.permanentDismissCountKey)
        if permanentDismissCount >= 5 {
            setUserDisabled(true)
        } else {
            // Just dismiss today so the banner goes away now.
            dismissForToday(today: today)
        }
    }

    func setUserDisabled(_ disabled: Bool) {
        isUserDisabled = disabled
        UserDefaults.standard.set(disabled, forKey: Self.disabledKey)
    }

    func resetAll() {
        lastShownDate = nil
        dismissedDates = []
        permanentDismissCount = 0
        isUserDisabled = false
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.lastShownKey)
        d.removeObject(forKey: Self.dismissedDatesKey)
        d.removeObject(forKey: Self.permanentDismissCountKey)
        d.removeObject(forKey: Self.disabledKey)
    }

    private static func dateKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
