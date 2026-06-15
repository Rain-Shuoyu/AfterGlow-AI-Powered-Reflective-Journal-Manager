import Foundation

/// "📓 自我追问" — questions the AI pulls out of the user's
/// own past writing that the user hasn't answered yet.
///
/// Three kinds of questions:
///   - `.unresolved`: 3 months ago you wanted to make a
///     decision. Did you?
///   - `.definition`: You mentioned "freedom" in 6 entries.
///     What does it mean to you?
///   - `.emotion`: "Tired" has come up a lot lately. When did
///     it start?
///
/// The cache is monthly — we don't want to re-run the LLM on
/// every open. The user can hit "换一批" to force a refresh.
struct SelfQuestion: Identifiable, Hashable, Codable {
    let id: String
    let kind: Kind
    let text: String           // "你 3 个月前想做那个决定，后来呢？"
    let sourceDate: Date?      // for `.unresolved`: the date of the entry that surfaced it
    let sourceEntryId: String?
    let createdAt: Date

    enum Kind: String, Codable, Hashable {
        case unresolved
        case definition
        case emotion
    }
}
