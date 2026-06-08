import Foundation

/// Mutable in-progress state for the diary editor. Lives only in memory
/// (not persisted) — the only thing that gets written to disk is the
/// serialized markdown produced from this state.
struct EditorState: Equatable {
    var date: Date
    var title: String
    var mood: Int?              // 1...5
    var moodLabel: String       // free-form
    var weather: String
    var tags: [String]
    var body: String            // raw markdown (already has the heading structure)

    // For "editing an existing entry". nil = new entry.
    var editingURL: URL?
    var originalFilename: String?

    // The user's draft is "dirty" once anything diverges from what was
    // loaded. Used to gate Cmd+S / show the unsaved indicator.
    var isDirty: Bool = false

    /// New-entry body template is intentionally **empty** — the
    /// `> 今日一句话` blockquote we used to ship made the user think
    /// they couldn't type into the body (the `> ` marker is hidden by
    /// the live renderer, so the line reads as "stuck cursor" instead
    /// of "your space to write").
    static let defaultBodyTemplate = ""

    static func forNewEntry() -> EditorState {
        EditorState(
            date: Date(),
            title: "",
            mood: nil,
            moodLabel: "",
            weather: "",
            tags: [],
            body: defaultBodyTemplate,
            editingURL: nil,
            originalFilename: nil,
            isDirty: false
        )
    }

    static func from(entry: DiaryEntry) -> EditorState {
        EditorState(
            date: entry.date,
            title: entry.frontmatter.title ?? entry.title,
            mood: entry.frontmatter.mood,
            moodLabel: entry.frontmatter.moodLabel ?? "",
            weather: entry.frontmatter.weather ?? "",
            tags: entry.frontmatter.tags,
            body: entry.rawContent,
            editingURL: entry.url,
            originalFilename: entry.url.lastPathComponent,
            isDirty: false
        )
    }
}
