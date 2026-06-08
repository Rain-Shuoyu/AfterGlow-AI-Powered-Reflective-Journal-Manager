import Foundation

/// Serializes an `EditorState` (header fields + body) into a complete
/// markdown file with YAML frontmatter, matching the format `DiaryParser`
/// already understands. Pure value transformation — no I/O. The caller
/// (`DiaryStore`) handles actually writing the bytes to disk.
enum MarkdownSerializer {

    /// Build the full .md file content from an editor state.
    /// - Parameters:
    ///   - state: the in-progress edit
    ///   - style: how to write tags — `.inline` (`tags: [a, b]`) matches
    ///            what the sample diaries use; `.block` (`tags:\n  - a`)
    ///            is what `DiaryParser` round-trips through. We use `.block`
    ///            so unknown tags are unambiguously preserved.
    static func serialize(_ state: EditorState, tagsStyle: TagsStyle = .block) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("date: \(dateString(state.date))")
        if let mood = state.mood {
            lines.append("mood: \(mood)")
        }
        if !state.moodLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("mood_label: \(escapeYaml(state.moodLabel))")
        }
        if !state.weather.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("weather: \(escapeYaml(state.weather))")
        }
        if !state.title.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("title: \(escapeYaml(state.title))")
        }
        if !state.tags.isEmpty {
            switch tagsStyle {
            case .inline:
                let joined = state.tags
                    .map { escapeYaml($0) }
                    .joined(separator: ", ")
                lines.append("tags: [\(joined)]")
            case .block:
                lines.append("tags:")
                for tag in state.tags {
                    lines.append("  - \(escapeYaml(tag))")
                }
            }
        }
        lines.append("---")
        lines.append("")
        // Body. Trim leading newlines only (preserve any trailing blank
        // lines the user wants for spacing).
        let body = state.body.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        lines.append(body)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Filename for a new entry: `YYYY-MM-DD.md`.
    /// Appends `-2`, `-3`, ... if the target file already exists in `folder`.
    static func availableFilename(for date: Date, in folder: URL) -> String {
        let base = dateString(date)
        var candidate = "\(base).md"
        var n = 1
        let fm = FileManager.default
        while fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            n += 1
            candidate = "\(base)-\(n).md"
        }
        return candidate
    }

    enum TagsStyle { case inline, block }

    // MARK: - helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Quote YAML scalars that contain colons, hash signs, or leading
    /// special chars; pass everything else through plain.
    private static func escapeYaml(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "\"\"" }
        let needsQuoting =
            trimmed.contains(":") ||
            trimmed.contains("#") ||
            trimmed.hasPrefix("-") ||
            trimmed.hasPrefix("[") ||
            trimmed.hasPrefix("'") ||
            trimmed.hasPrefix("\"")
        if needsQuoting {
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return trimmed
    }
}
