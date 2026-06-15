import SwiftUI

/// "🌙 今日签" sheet — the daily micro-practice ritual.
///
/// The user can:
///   - read today's prompt (always the same for the whole day)
///   - write a 1-2 minute reflection in the optional text field
///   - tap "我写完了 ✓" to mark today done and bump the streak
///   - tap "跳过" to dismiss without recording (the prompt stays
///     the same; they can come back later)
///   - tap "✕" to dismiss without recording
///
/// If today already has a diary entry, "我写完了" *appends* the
/// answer to that diary's body and updates the frontmatter
/// `daily_practice` field. If no entry exists, a new one is
/// created with the prompt + answer as the body. The mood
/// defaults to nil (let the AI infer it from the text on next
/// reload).
struct DailyPracticeSheet: View {

    @EnvironmentObject var store: DailyPracticeStore
    @EnvironmentObject var diaryStore: DiaryStore
    @Environment(\.dismiss) private var dismiss

    /// The current prompt the sheet is showing. Captured at sheet
    /// open so it doesn't change if the day rolls over mid-view.
    @State private var prompt: DailyPractice.Prompt
    @State private var answer: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?

    init() {
        // Pre-compute today's prompt so the sheet content is
        // stable for its whole lifetime.
        let today = DailyPractice.pick()
        _prompt = State(initialValue: today)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    promptCard
                    if !store.isTodayDone || isEditingAfterDone {
                        answerField
                        saveErrorView
                    } else {
                        doneFooter
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 540, height: 540)
        .background(
            ZStack {
                Color(white: 0.07)
                // Subtle moon glow under the prompt
                RadialGradient(
                    colors: [DS.Brand.amber.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0.18),
                    startRadius: 0,
                    endRadius: 220
                )
            }
            .ignoresSafeArea()
        )
        .onAppear {
            // If today is already done, prefill the answer with
            // what the user wrote earlier.
            if let existing = existingTodayAnswer, !existing.isEmpty {
                answer = existing
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("🌙")
                        .font(.system(size: 18))
                    Text("今日签")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(streakSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var streakSubtitle: String {
        switch store.streakStatus {
        case .active(let n, true):
            return "\(formattedDate) · 连续 \(n) 天 🔥"
        case .active(let n, false):
            return "\(formattedDate) · 连续 \(n) 天（今日未完成）"
        case .short:
            return "\(formattedDate) · 今日尚未完成"
        case .none:
            return formattedDate
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd EEEE"
        return f.string(from: Date())
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(prompt.category.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Brand.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(DS.Brand.amber.opacity(0.12))
                    )
                Spacer()
            }
            Text(prompt.text)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.Brand.amber.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Answer field

    @FocusState private var answerFocused: Bool

    private var answerField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("写下你的回答（可选）")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Brand.warmGray)
            ZStack(alignment: .topLeading) {
                if answer.isEmpty && !answerFocused {
                    Text("1-2 句就够。哪怕只写一个字也好。")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $answer)
                    .focused($answerFocused)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .frame(minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                answerFocused
                                    ? DS.Brand.amber.opacity(0.4)
                                    : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
            )
        }
    }

    // MARK: - Done footer (when today is already marked done)

    private var doneFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.Brand.amber)
                Text("今日已完成")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("如果想补充，可以再写一段。")
                .font(.system(size: 12))
                .foregroundStyle(DS.Brand.warmGray)
        }
    }

    // MARK: - Save error

    @ViewBuilder
    private var saveErrorView: some View {
        if let err = saveError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
        }
    }

    // MARK: - Footer (action buttons)

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("跳过")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Brand.warmGray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: store.isTodayDone ? "square.and.pencil" : "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(store.isTodayDone ? "更新记录" : "我写完了")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Brand.amber)
            )
            .disabled(isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Save logic

    private var isEditingAfterDone: Bool {
        store.isTodayDone && !existingTodayAnswer.isEmptyOrNil
    }

    private var existingTodayAnswer: String? {
        guard let entry = diaryStore.entries.first(where: {
            Calendar.current.isDateInToday($0.date)
        }) else { return nil }
        // The body of the daily-practice entry has a marker line
        // we add at save time; the user's answer is everything
        // after it. We re-derive the answer by looking at the
        // body lines after the first "## " heading.
        return extractAnswer(from: entry.rawContent)
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        // If empty, treat "我写完了" as "I just want to mark it
        // done, no text". Still record the prompt in frontmatter
        // so the streak is recorded.
        do {
            try await persistDailyPractice(answerText: trimmed)
            store.markTodayDone()
            // Refresh diary store so the file shows up in the
            // 写作 tab immediately.
            diaryStore.reload()
            dismiss()
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }

    private func persistDailyPractice(answerText: String) async throws {
        // Locate the file URL for today's diary (if any).
        let todayKey: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()
        let existingURL = diaryStore.entries
            .first(where: { Calendar.current.isDateInToday($0.date) })?
            .url

        guard let diaryRoot = diaryStore.folderURL else {
            throw NSError(
                domain: "DailyPractice",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "尚未选择日记目录"]
            )
        }
        let targetURL: URL = existingURL
            ?? diaryRoot.appendingPathComponent("\(todayKey).md")

        // Build the body. Frontmatter is handled per branch below.
        var body = ""
        if !answerText.isEmpty {
            body = "## 🌙 今日签\n\n> \(prompt.text)\n\n\(answerText)\n"
        } else {
            body = "## 🌙 今日签\n\n> \(prompt.text)\n\n_（已确认今日完成）_\n"
        }

        if existingURL != nil {
            // Read existing file, replace or insert the section.
            let existing = try String(contentsOf: existingURL!, encoding: .utf8)
            let (existingFM, existingBody) = splitFrontmatterAndBody(existing)
            let newBody = injectOrReplaceSection(
                in: existingBody,
                heading: "## 🌙 今日签",
                newBody: body
            )
            let updated = existingFM + newBody
            try updated.write(to: existingURL!, atomically: true, encoding: .utf8)
        } else {
            // New file — write a minimal frontmatter + the section.
            // We avoid touching the frontmatter struct so we don't
            // need to plumb daily_practice fields through the
            // existing Frontmatter model. The prompt goes in the
            // body as a markdown blockquote so the diary parser
            // still sees a normal markdown file.
            let newFM = "---\n" +
                "date: \(todayKey)\n" +
                "title: \"今日签\"\n" +
            "---\n\n"
            let full = newFM + body
            try full.write(to: targetURL, atomically: true, encoding: .utf8)
        }
    }

    private func extractAnswer(from body: String) -> String? {
        let marker = "## 🌙 今日签"
        guard let range = body.range(of: marker) else { return nil }
        let after = body[range.upperBound...]
        // Skip past the prompt blockquote and any blank lines
        var lines = after.split(separator: "\n", omittingEmptySubsequences: false)
        // Drop first 4 lines: blank, '> ...', blank, '> ...'
        // (defensive — the section has 2 blockquote lines)
        if lines.count > 4 {
            lines = Array(lines.dropFirst(4))
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "_（已确认今日完成）_" {
            return ""
        }
        return text
    }

    private func splitFrontmatterAndBody(_ content: String) -> (String, String) {
        guard content.hasPrefix("---\n") else { return ("", content) }
        if let fmEndRange = content.range(of: "\n---\n", range: content.index(after: content.startIndex)..<content.endIndex) {
            let front = String(content[..<fmEndRange.upperBound])
            let body = String(content[fmEndRange.upperBound...])
            return (front, body)
        }
        return ("", content)
    }

    private func injectOrReplaceSection(in body: String, heading: String, newBody: String) -> String {
        if let range = body.range(of: heading) {
            // Replace the section up until the next "## " or end of
            // body.
            let afterRange = range.upperBound..<body.endIndex
            let after = body[afterRange]
            // Find next heading at same level (## or higher)
            var endIndex = body.endIndex
            if let next = after.range(of: "\n## ") {
                endIndex = next.lowerBound
            }
            return String(body[..<range.lowerBound]) + newBody + String(body[endIndex...])
        } else {
            return body + "\n" + newBody
        }
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}
