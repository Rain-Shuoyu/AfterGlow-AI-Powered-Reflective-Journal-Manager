import Foundation

/// "🌧 情绪急救" — a one-line mood log + intervention signal.
///
/// The mood-quick is the lightest possible self-report:
///   - 1 emoji (😔 😐 🙂 😊)
///   - 1 short line of free text (max 60 chars)
/// It is intentionally *not* the 5-step mood scale. We don't
/// want users to feel they're being graded — we just want a
/// quick "what's the weather inside you right now" check-in.
///
/// Storage: the `mood_quick` frontmatter field on today's diary
/// (handled by `MoodQuickStore`). The mood emoji + text are
/// joined with a single space, e.g. `"😔 撑了一天"`.
struct MoodQuick: Codable, Hashable {
    let emoji: String         // one of 😔 / 😐 / 🙂 / 😊
    let text: String          // free text, 0-60 chars

    static let allowedEmojis = ["😔", "😐", "🙂", "😊"]

    /// "Score" used by the rescue-signal detector:
    ///   - 😔 → 1 (low)
    ///   - 😐 → 2
    ///   - 🙂 → 3
    ///   - 😊 → 4 (high)
    /// Note: the user's typed text can also signal distress via
    /// `MoodQuickStore.triggerKeywords`, which is checked in
    /// addition to the emoji score.
    var score: Int {
        switch emoji {
        case "😔": return 1
        case "😐": return 2
        case "🙂": return 3
        case "😊": return 4
        default:   return 2
        }
    }
}
