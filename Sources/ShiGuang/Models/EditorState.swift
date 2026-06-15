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

    /// Pre-filled state for the "✍️ 现在写一封" flow. Title gets the
    /// scenario's display name; body is seeded with a "## 信" section
    /// containing the LLM-generated opening (caller passes the opening
    /// text in). The `tags` carry the scenario id so the entry can be
    /// retrieved / filtered later as a letter.
    static func forLetter(scenario: LetterPrompt.Scenario, opening: String = "") -> EditorState {
        let titleText = "给\(scenario.displayName)的信"
        let bodyText: String
        if opening.isEmpty {
            bodyText = "## 给\(scenario.displayName)的信\n\n"
        } else {
            bodyText = "## 给\(scenario.displayName)的信\n\n\(opening)\n\n"
        }
        return EditorState(
            date: Date(),
            title: titleText,
            mood: nil,
            moodLabel: "",
            weather: "",
            tags: ["letter", scenario.id],
            body: bodyText,
            editingURL: nil,
            originalFilename: nil,
            isDirty: false
        )
    }

    /// Pre-filled state for the "📓 待回答" flow. The body is
    /// seeded with a callout block containing the question,
    /// followed by a blank line for the user to write. The
    /// `tags` carry the question id so the entry can be
    /// linked back to the question that prompted it.
    static func forQuestion(_ q: SelfQuestion) -> EditorState {
        let body = "## 待回答：\(kindLabel(q.kind))\n\n> \(q.text)\n\n"
        return EditorState(
            date: Date(),
            title: kindLabel(q.kind),
            mood: nil,
            moodLabel: "",
            weather: "",
            tags: ["self-question", q.id],
            body: body,
            editingURL: nil,
            originalFilename: nil,
            isDirty: false
        )
    }

    private static func kindLabel(_ k: SelfQuestion.Kind) -> String {
        switch k {
        case .unresolved: return "悬而未决"
        case .definition: return "自我定义"
        case .emotion:    return "情绪主题"
        }
    }
}
