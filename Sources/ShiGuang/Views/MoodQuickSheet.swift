import SwiftUI

/// "🌧 1 行情绪" sheet — the lightest possible mood log.
///
/// 4 emoji buttons + a single short text field. Saved into
/// today's diary frontmatter as `mood_quick: "😔 撑了一天"`.
///
/// Why not the 5-step mood scale? The scale feels like a grade.
/// The emoji + 1 line is just "what's the weather inside you
/// right now" — no judgment, no score.
struct MoodQuickSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var diaryStore: DiaryStore

    @State private var emoji: String = "😐"
    @State private var text: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 22) {
                emojiRow
                textField
                if let err = saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                saveButton
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 460, height: 380)
        .background {
            ZStack {
                Color(white: 0.07)
                RadialGradient(
                    colors: [DS.Brand.amber.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.5, y: 0.2),
                    startRadius: 0,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("🌧")
                        .font(.system(size: 18))
                    Text("现在感觉")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("一句话就够。1 秒钟可以关掉。")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Emoji row

    private var emojiRow: some View {
        HStack(spacing: 12) {
            ForEach(MoodQuick.allowedEmojis, id: \.self) { e in
                Button {
                    emoji = e
                } label: {
                    Text(e)
                        .font(.system(size: 32))
                        .frame(width: 56, height: 56)
                        .background {
                            Circle()
                                .fill(emoji == e
                                      ? DS.Brand.amber.opacity(0.25)
                                      : Color.white.opacity(0.05))
                        }
                        .overlay(
                            Circle()
                                .stroke(
                                    emoji == e
                                        ? DS.Brand.amber
                                        : Color.white.opacity(0.1),
                                    lineWidth: emoji == e ? 1.5 : 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Text field

    @FocusState private var textFocused: Bool

    private var textField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("想说什么（可选）")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Brand.warmGray)
            ZStack(alignment: .topLeading) {
                if text.isEmpty && !textFocused {
                    Text("一句话就够，也可以不写")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text, axis: .vertical)
                    .focused($textFocused)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1...3)
                    .onChange(of: text) { _, newValue in
                        // Hard cap at 60 chars.
                        if newValue.count > 60 {
                            text = String(newValue.prefix(60))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                textFocused
                                    ? DS.Brand.amber.opacity(0.4)
                                    : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
            )
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        HStack {
            Spacer()
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(isSaving ? "保存中…" : "记下来")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(DS.Brand.amber)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await persistMoodQuick()
            diaryStore.reload()
            dismiss()
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }

    /// Write the mood_quick into today's diary frontmatter. If
    /// no diary exists, create one. If one exists, update the
    /// `mood_quick` extra key (don't touch other frontmatter).
    private func persistMoodQuick() async throws {
        guard let folder = diaryStore.folderURL else {
            throw NSError(
                domain: "MoodQuick",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "尚未选择日记目录"]
            )
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let todayKey = f.string(from: Date())
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quickValue = trimmedText.isEmpty
            ? emoji
            : "\(emoji) \(trimmedText)"

        let targetURL = diaryStore.entries
            .first(where: { Calendar.current.isDateInToday($0.date) })?
            .url ?? folder.appendingPathComponent("\(todayKey).md")

        if FileManager.default.fileExists(atPath: targetURL.path) {
            let existing = try String(contentsOf: targetURL, encoding: .utf8)
            let updated = upsertExtraKey(
                in: existing,
                key: "mood_quick",
                value: quickValue
            )
            try updated.write(to: targetURL, atomically: true, encoding: .utf8)
        } else {
            let frontmatter = "---\n" +
                "date: \(todayKey)\n" +
                "mood_quick: \"\(quickValue)\"\n" +
            "---\n\n"
            try frontmatter.write(to: targetURL, atomically: true, encoding: .utf8)
        }
    }

    /// Insert or replace a top-level YAML key in a frontmatter
    /// block. If the block doesn't exist, prepend a new one.
    private func upsertExtraKey(in content: String, key: String, value: String) -> String {
        // Detect frontmatter
        guard content.hasPrefix("---\n") else {
            return "---\n\(key): \"\(value)\"\n---\n\n" + content
        }
        if let endRange = content.range(of: "\n---\n", range: content.index(after: content.startIndex)..<content.endIndex) {
            let fmBody = String(content[..<endRange.lowerBound])  // incl. last "\n"
            let rest = String(content[endRange.upperBound...])
            let fmNoTrailingNewline = fmBody.hasSuffix("\n")
                ? String(fmBody.dropLast())
                : fmBody
            // Check if key exists
            let pattern = "^\(NSRegularExpression.escapedPattern(for: key))\\s*:"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
               regex.firstMatch(in: fmNoTrailingNewline,
                                range: NSRange(location: 0, length: fmNoTrailingNewline.utf16.count)) != nil {
                // Replace existing line
                let lines = fmNoTrailingNewline.components(separatedBy: "\n")
                let newLines = lines.map { line -> String in
                    if line.hasPrefix("\(key):") {
                        return "\(key): \"\(value)\""
                    }
                    return line
                }
                return newLines.joined(separator: "\n") + "\n---\n\n" + rest
            } else {
                return fmNoTrailingNewline + "\n\(key): \"\(value)\"\n---\n\n" + rest
            }
        }
        return "---\n\(key): \"\(value)\"\n---\n\n" + content
    }
}
