import SwiftUI

/// "回溯" sheet — picks a random past diary entry, asks the LLM to
/// summarise what happened, the mood, and an insight, and renders the
/// result in a sheet that matches the style of the editor and the
/// timeline's `DiaryDetailSheet` (same backdrop, same close button,
/// same padding system).
///
/// The title bar reads "你知道吗？" — the body below is the
/// streaming LLM output, structured as three short Markdown
/// sections: 「那天做了什么 / 心情 / 启发」.
struct FlashbackSheet: View {
    let entry: DiaryEntry
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    // Streaming state. We accumulate the model's response into
    // `content` and clear `isLoading` once the first chunk arrives,
    // so the user sees a partial answer fill in instead of staring
    // at a spinner.
    @State private var content: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    if let err = error {
                        // Surface the LLM error in-flow rather than a
                        // modal alert — keeps the user inside the
                        // sheet so they can retry or close.
                        VStack(alignment: .leading, spacing: 6) {
                            Label("回溯失败", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.callout.weight(.semibold))
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(DS.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .fill(.red.opacity(0.10))
                        }
                    } else {
                        if content.isEmpty {
                            placeholderLines
                        } else {
                            MarkdownText(markdown: content, baseFont: .body)
                        }
                    }
                }
                .padding(DS.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            // Same backdrop as the editor + DiaryDetailSheet so the
            // three sheets feel like one family.
            ZStack {
                LiquidBackdrop().ignoresSafeArea()
                Color.clear
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NSWorkspace.shared.open(entry.url)
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }
        }
        .onAppear { start() }
        .onDisappear { task?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(DS.Brand.amberDeep)
                    Text("你知道吗？")
                        .font(.largeTitle.weight(.semibold))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            // Meta line: date + mood dot + tags, same shape as
            // DiaryDetailSheet's header so the user immediately
            // recognises this is "another entry, but reinterpreted".
            HStack(spacing: 8) {
                Text(entry.date.short)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let m = entry.frontmatter.mood {
                    HStack(spacing: 4) {
                        Circle().fill(DS.Mood.color(m)).frame(width: 8, height: 8)
                        Text("mood \(m)/5").font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(DS.Mood.color(m).opacity(0.15)))
                }
                if !entry.frontmatter.tags.isEmpty {
                    ForEach(entry.frontmatter.tags.prefix(4), id: \.self) { t in
                        Text(t)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(DS.Brand.amberSoft))
                    }
                }
            }
            if !entry.title.isEmpty && entry.title != "无标题" {
                Text(entry.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.l)
    }

    /// Three ghost lines shown while we wait for the first LLM
    /// chunk. Pulsing amber to signal "thinking…".
    private var placeholderLines: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3) { _ in
                Capsule(style: .continuous)
                    .fill(DS.Brand.amber.opacity(0.18))
                    .frame(height: 14)
            }
            Capsule(style: .continuous)
                .fill(DS.Brand.amber.opacity(0.10))
                .frame(width: 220, height: 14)
        }
    }

    // MARK: - Streaming

    /// Build the LLM request and stream it into `content`.
    /// Reusing the streaming + StreamParser pattern from ChatView
    /// so the two surfaces feel consistent.
    private func start() {
        task?.cancel()
        content = ""
        isLoading = true
        error = nil
        task = Task { @MainActor in
            do {
                let client = try LLMClientFactory.make(settings: settings)
                let req = ChatRequest(
                    messages: [
                        ChatMessage(role: .system, content: Self.systemPrompt),
                        ChatMessage(role: .user, content: Self.userPrompt(for: entry))
                    ],
                    model: settings.model,
                    temperature: 0.6
                )
                let parser = StreamParser()
                try await client.stream(req) { chunk in
                    let (_, contentDelta) = parser.feed(chunk)
                    await MainActor.run {
                        if !contentDelta.isEmpty {
                            content += contentDelta
                            // Once we've got a real chunk, drop
                            // the placeholder shimmer.
                            if isLoading { isLoading = false }
                        }
                    }
                }
                // Flush any tag that was split across chunks.
                let (_, finalContent) = parser.flush()
                if !finalContent.isEmpty {
                    content += finalContent
                }
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Prompts

    private static let systemPrompt: String = """
    你是一个私人日记回溯助手，正在帮用户从过去的某篇日记里提取洞察。

    要求：
    1. 严格只根据提供的日记内容作答，不要编造事件或日期。
    2. 用中文回答，结构化 Markdown。
    3. 输出**三个**小节（每个用 ## 二级标题，emoji 前缀），每节 2–4 句：
       - ## 📅 那天做了什么 — 概括当天的事件、活动
       - ## 🌡 心情 — 描述当天的情绪状态、波动
       - ## 💡 启发 — 从今天的视角回看，能看到什么线索、模式或值得记住的事
    4. 文字克制、温暖、不说教。
    5. 严禁"让我分析一下"等开场白，开门见山。
    """

    /// Builds the per-entry user prompt. We pass the trimmed
    /// diary body so the model can read the full text without
    /// blowing the context window (a single day's entry is
    /// usually < 2000 chars, well under M2.7's 1M context).
    private static func userPrompt(for entry: DiaryEntry) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return """
        下面是用户某一天（\(df.string(from: entry.date))）写的日记：

        ---
        \(entry.plainText)
        ---

        请按要求的三段式输出。
        """
    }
}

// MARK: - Entry picker

extension FlashbackSheet {
    /// Pick a random entry. Uniform random over `entries` is
    /// good enough — we want a "show me a memory I haven't looked
    /// at in a while" feel, not a curated selection.
    static func pickRandom(from entries: [DiaryEntry]) -> DiaryEntry? {
        guard !entries.isEmpty else { return nil }
        return entries.randomElement()
    }
}
