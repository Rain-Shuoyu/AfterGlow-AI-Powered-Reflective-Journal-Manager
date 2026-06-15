import Foundation
import SwiftUI

/// Local-only state for the "🌙 今日签" daily practice.
///
/// Tracks:
///   - the most-recent streak of consecutive days the user marked
///     "我写完了" (gentle streak — never penalises breaks)
///   - the date of the last completion (so the UI can say "你昨天
///     完成了，已连续 N 天")
///   - the last-completed prompt id (so we can detect "you already
///     finished today's prompt" and show a different CTA)
@MainActor
final class DailyPracticeStore: ObservableObject {

    // MARK: - Persistence keys

    private static let lastDoneDateKey  = "DiaryInsight.DailyPractice.lastDoneDate"
    private static let lastDonePromptKey = "DiaryInsight.DailyPractice.lastDonePromptId"
    private static let streakKey        = "DiaryInsight.DailyPractice.streak"
    private static let longestStreakKey = "DiaryInsight.DailyPractice.longestStreak"

    // MARK: - Published state

    @Published private(set) var streak: Int
    @Published private(set) var longestStreak: Int
    @Published private(set) var lastDoneDate: Date?
    /// The id (index) of the prompt that was completed on `lastDoneDate`.
    /// `nil` if we've never completed one.
    @Published private(set) var lastDonePromptId: Int?

    init() {
        let d = UserDefaults.standard
        self.streak = d.object(forKey: Self.streakKey) as? Int ?? 0
        self.longestStreak = d.object(forKey: Self.longestStreakKey) as? Int ?? 0
        self.lastDoneDate = d.object(forKey: Self.lastDoneDateKey) as? Date
        self.lastDonePromptId = d.object(forKey: Self.lastDonePromptKey) as? Int
    }

    // MARK: - Derived state

    /// The prompt the user should see right now. Always today's
    /// pick — *not* the last-completed one — so the prompt is
    /// stable for the whole day.
    var todayPrompt: DailyPractice.Prompt { DailyPractice.pick() }

    /// True iff the user has already marked "我写完了" for today's
    /// prompt.
    var isTodayDone: Bool {
        guard let last = lastDoneDate else { return false }
        return Calendar.current.isDateInToday(last)
            && lastDonePromptId == todayPrompt.id
    }

    /// Streak label for the UI, e.g. "🔥 连续 7 天" / "已连续 3 天"
    /// / "今日尚未完成".
    var streakStatus: StreakStatus {
        if isTodayDone {
            if streak >= 3 {
                return .active(streak: streak, isTodayDone: true)
            } else {
                return .short
            }
        } else if streak >= 3 {
            // Yesterday's streak is still "alive" — we don't reset
            // the count until the user skips a full day.
            return .active(streak: streak, isTodayDone: false)
        } else {
            return .none
        }
    }

    enum StreakStatus: Equatable {
        case none                // streak < 3 and today not done
        case short               // streak < 3 but user engaged recently
        case active(streak: Int, isTodayDone: Bool)
    }

    // MARK: - Mutations

    /// Mark today's prompt as done. Bumps the streak if the user
    /// also did it yesterday; resets to 1 if they skipped; stays
    /// at 0 if they haven't done one before.
    func markTodayDone() {
        let now = Date()
        let cal = Calendar.current
        let prevStreak = streak
        let prevDate = lastDoneDate

        // Compute the new streak:
        //   - first ever completion → 1
        //   - did it yesterday → prev + 1
        //   - already did it today (re-tap) → no change
        //   - skipped ≥ 1 day → reset to 1
        if let prev = prevDate, cal.isDateInToday(prev), prevDonePromptIdMatchesToday() {
            // already done today — idempotent
            return
        }
        if let prev = prevDate, cal.isDateInYesterday(prev) {
            streak = prevStreak + 1
        } else {
            streak = 1
        }
        lastDoneDate = now
        lastDonePromptId = todayPrompt.id
        longestStreak = max(longestStreak, streak)

        let d = UserDefaults.standard
        d.set(streak, forKey: Self.streakKey)
        d.set(longestStreak, forKey: Self.longestStreakKey)
        d.set(now, forKey: Self.lastDoneDateKey)
        d.set(todayPrompt.id, forKey: Self.lastDonePromptKey)
    }

    /// Reset all streak counters + last-done state. Used by
    /// the Settings → 仪式感 → "重置 streak" button. This is the
    /// only way the user can clear their streak without
    /// reinstalling the app.
    func resetStreaks() {
        streak = 0
        longestStreak = 0
        lastDoneDate = nil
        lastDonePromptId = nil
        let d = UserDefaults.standard
        d.set(0, forKey: Self.streakKey)
        d.set(0, forKey: Self.longestStreakKey)
        d.removeObject(forKey: Self.lastDoneDateKey)
        d.removeObject(forKey: Self.lastDonePromptKey)
    }

    private func prevDonePromptIdMatchesToday() -> Bool {
        lastDonePromptId == todayPrompt.id
    }
}
