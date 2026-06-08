import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isAsking: Bool = false
    @State private var lastError: String?
    @State private var lastFilterExplanation: String = ""

    private let suggestedQuestions: [String] = [
        "我六月份有哪些天心情不好？",
        "最近一个月我都关心些什么？",
        "我和家人之间发生过哪些冲突？",
        "我这一年的情绪变化趋势是什么？",
        "哪些天我最焦虑？",
        "总结一下我过去三个月的工作状态"
    ]

    var body: some View {
        VStack(spacing: 0) {
            conversationList
            inputBar
        }
        .navigationTitle("")
        .toolbar(.hidden)
    }

    // MARK: - Conversation

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    if messages.count <= 1 {
                        suggestionsGrid
                    } else {
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            ForEach(messages.dropFirst()) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                    }
                    if let err = lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, DS.Spacing.m)
                    }
                    if !lastFilterExplanation.isEmpty {
                        Text("检索：\(lastFilterExplanation)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DS.Spacing.m)
                    }
                    if isAsking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在思考…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, DS.Spacing.m)
                    }
                }
                .padding(DS.Spacing.xl)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: messages.last?.content.count ?? 0) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var suggestionsGrid: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Hero — animated glow + brand mark. This is the focal point
            // of the empty state, intentionally centred rather than
            // left-aligned so the eye lands here first.
            heroBlock

            // Capability cards — the four main things the AI can do.
            // Each card is a one-tap shortcut that fires a richer,
            // category-specific question (instead of a generic one).
            capabilityCards

            // Quick chips below — the original suggestion list, now
            // demoted to "or try one of these" so it doesn't compete
            // with the cards.
            quickChips
        }
    }

    // MARK: - Hero

    @State private var heroPulse: CGFloat = 1.0   // outer glow scale
    @State private var moonBob:   CGFloat = 0      // moon Y translation
    @State private var glowOpacity: Double = 0.45

    private var heroBlock: some View {
        VStack(spacing: DS.Spacing.m) {
            ZStack {
                // ── 1. Outer pulse ───────────────────────────────────
                // Big radial glow that breathes 1.0 ↔ 1.45 — clearly
                // visible against the dark page background. Sits
                // behind the mark and gives the moon a place to
                // shine from.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DS.Brand.amber.opacity(0.55),
                                DS.Brand.amber.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .scaleEffect(heroPulse)
                    .opacity(glowOpacity)

                // ── 3. The app mark (book + floating moon) ───────────
                // Pure SwiftUI vector — every curve is a real
                // Bezier / arc, so it stays crisp at any size and
                // blends with any background. The moon is a
                // separate layer from the book, so we can animate
                // just the moon's Y for the "floating" effect.
                AppLogoMark(size: 128, moonOffsetY: moonBob)
                    .frame(width: 128, height: 128)
            }
            .onAppear {
                // Outer glow breath — 2.5s, dramatic enough to read.
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    heroPulse = 1.45
                }
                // Glow opacity also breathes so the halo doesn't just
                // change size — it also brightens and fades.
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.85
                }
                // The moon itself bobs up and down — 6pt, slow. The
                // book is stationary so the visual reads as "the moon
                // is floating above the book".
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    moonBob = -6
                }
            }

            VStack(spacing: 4) {
                Text("拾光")
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                Text("用 AI 重新看见你的日记")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, DS.Spacing.l)
    }

    // MARK: - Capability cards

    /// A shortcut card. Tap fires `question` and lets the model take it
    /// from there. The title + subtitle are user-facing labels so the
    /// user knows what they're asking before they tap.
    private struct Capability: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let question: String
    }

    private let capabilities: [Capability] = [
        .init(
            id: "mood",
            icon: "heart.text.square.fill",
            title: "情绪洞察",
            subtitle: "近期的 mood 走向、模式、转折点",
            question: "分析我最近的 mood 走向和情绪模式"
        ),
        .init(
            id: "time",
            icon: "calendar.badge.clock",
            title: "时间回顾",
            subtitle: "总结某个时间段发生了什么",
            question: "总结一下我过去一周的生活"
        ),
        .init(
            id: "people",
            icon: "person.2.wave.2.fill",
            title: "关系脉络",
            subtitle: "和家人 / 朋友 / 同事的互动",
            question: "我和家人之间最近有过哪些冲突或重要时刻？"
        ),
        .init(
            id: "pattern",
            icon: "sparkle.magnifyingglass",
            title: "主题发现",
            subtitle: "反复出现的关键词、生活主题",
            question: "我最近反复出现的主题是什么？"
        ),
    ]

    private var capabilityCards: some View {
        // 2x2 grid. The 4 cards cover the 4 broad things a user might
        // want from a diary AI; tapping any one is more discoverable
        // than a freeform text prompt for new users.
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: DS.Spacing.m),
                      GridItem(.flexible(), spacing: DS.Spacing.m)],
            spacing: DS.Spacing.m
        ) {
            ForEach(capabilities) { cap in
                Button { send(cap.question) } label: {
                    capabilityCard(cap)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func capabilityCard(_ cap: Capability) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .top) {
                Image(systemName: cap.icon)
                    .font(.title3)
                    .foregroundStyle(DS.Brand.amberDeep)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(DS.Brand.amber.opacity(0.18))
                    }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(cap.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .strokeBorder(DS.Brand.amber.opacity(0.15), lineWidth: 0.5)
        }
    }

    // MARK: - Quick chips

    private var quickChips: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis.bubble")
                    .font(.caption)
                Text("或者试试")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            FlowLayout(spacing: DS.Spacing.s) {
                ForEach(suggestedQuestions, id: \.self) { q in
                    Button { send(q) } label: {
                        Text(q)
                            .font(.caption)
                            .padding(.horizontal, DS.Spacing.s + 2)
                            .padding(.vertical, 6)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                            }
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        // Send button sits in the bottom-right corner of the text area.
        // The TextEditor has right/bottom padding so its text never runs
        // under the button. Enter sends, Shift+Enter inserts a newline.
        // The whole bar is a single thin row (max ~44pt) using a thin
        // material so it floats over the background rather than blocking it.
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, DS.Spacing.s)
                .padding(.top, 6)
                .padding(.trailing, 44)  // room for the send button
                .padding(.bottom, 4)
                .frame(minHeight: 36, maxHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored  // let TextEditor insert newline
                    }
                    handleSend()
                    return .handled
                }

            Button {
                handleSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(DS.Brand.amber)
                            .squircle(DS.Radius.pill)
                    }
                    .foregroundStyle(DS.Brand.ink)
            }
            .buttonStyle(.plain)
            .padding(.trailing, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.s - 2)
            .disabled(isAsking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.s)
    }

    /// Trims the current input and sends it. Shared between the send button
    /// and the `↩` key handler in `onKeyPress`.
    private func handleSend() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        send(q)
        input = ""
    }

    // MARK: - Send

    private func send(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        if store.folderURL == nil {
            lastError = "请先到「统计」页选一个日记目录"
            return
        }
        if settingsStore.settings.apiKey.isEmpty {
            lastError = "请先到「设置」页填入 API Key"
            return
        }

        let userMsg = ChatMessage(role: .user, content: q)
        messages.append(userMsg)
        lastError = nil

        Task {
            await runAssistantTurn(question: q)
        }
    }

    @MainActor
    private func runAssistantTurn(question: String) async {
        isAsking = true
        defer { isAsking = false }

        let filter = DiaryIndexer.filter(
            entries: store.entries,
            for: question,
            maxResults: settingsStore.settings.maxContextEntries
        )
        lastFilterExplanation = "\(filter.entries.count)/\(filter.totalCandidates) 篇 — \(filter.explanation)"

        let context = buildContext(from: filter.entries)
        // The `enableThinking` setting is now wired into the request body as
        // `"thinking": false` for MiniMax M-series (see OpenAIClient.stream),
        // which disables the model's chain-of-thought at the server. The
        // system prompt just asks for structured Markdown output regardless.
        let systemPrompt = defaultSystemPrompt() + "\n\n" +
            (settingsStore.settings.systemPromptAddition.isEmpty ? "" : settingsStore.settings.systemPromptAddition + "\n\n") +
            "【检索到的相关日记片段】\n\(context)\n"

        var chatMessages = messages
        if chatMessages.first?.role == .system {
            chatMessages[0] = ChatMessage(role: .system, content: systemPrompt)
        } else {
            chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
        }

        // Pre-insert an empty assistant message; the streaming loop will
        // append each chunk to it in place so the user sees text arrive live.
        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", thinking: ""))
        let parser = StreamParser()

        do {
            let client = try LLMClientFactory.make(settings: settingsStore.settings)
            let req = ChatRequest(
                messages: chatMessages,
                model: settingsStore.settings.model,
                temperature: settingsStore.settings.temperature
            )
            try await client.stream(req) { chunk in
                let (thinkingDelta, contentDelta) = parser.feed(chunk)
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        if !thinkingDelta.isEmpty {
                            messages[idx].thinking = (messages[idx].thinking ?? "") + thinkingDelta
                        }
                        if !contentDelta.isEmpty {
                            messages[idx].content += contentDelta
                            messages[idx].content = postProcess(messages[idx].content)
                        }
                    }
                }
            }
            // Flush whatever the parser was still holding (tag split across chunks).
            let (finalThinking, finalContent) = parser.flush()
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if !finalThinking.isEmpty {
                    messages[idx].thinking = (messages[idx].thinking ?? "") + finalThinking
                }
                if !finalContent.isEmpty {
                    messages[idx].content += finalContent
                    messages[idx].content = postProcess(messages[idx].content)
                }
            }
        } catch {
            // Remove the empty placeholder so the user doesn't see a blank bubble.
            messages.removeAll { $0.id == assistantId }
            lastError = error.localizedDescription
        }
    }

    private func buildContext(from entries: [DiaryEntry]) -> String {
        if entries.isEmpty { return "（无匹配日记）" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return entries.map { e in
            """
            ### \(df.string(from: e.date)) — \(e.title)
            mood: \(e.frontmatter.mood.map(String.init) ?? "-")  tags: \(e.frontmatter.tags.joined(separator: ", "))
            \(truncate(e.plainText, to: 1200))
            """
        }.joined(separator: "\n\n")
    }

    private func truncate(_ s: String, to n: Int) -> String {
        if s.count <= n { return s }
        return String(s.prefix(n)) + "…(已截断)"
    }

    private func defaultSystemPrompt() -> String {
        """
        你是一个私人日记分析助手，名字叫"日记洞察"。你会阅读用户提供的若干篇日记摘录，\
        基于这些内容回答用户的问题、给出心理学视角的观察和建议。

        要求：
        1. 只根据提供的日记内容作答，不要编造不存在的事件或日期。
        2. 涉及具体日期时，直接引用日记原文的日期（YYYY-MM-DD）。
        3. 分析情绪/心理状态时，谨慎使用"抑郁症""焦虑症"等临床标签，倾向于描述性语言（"情绪持续低落""出现焦虑相关的语句"）。
        4. 回复使用中文，除非用户用其他语言提问。
        5. 结尾给一个简短的"建议/观察"，但不要做医疗诊断。
        6. 如果检索到的日记片段里没有相关信息，明确告诉用户"在已加载的日记里没找到对应内容"，并建议放宽时间范围或换关键词。

        【排版 — 每次回复必须遵守】
        - 至少 1 个 ## 二级标题 分段；多主题则每个主题一个 ##。
        - 引用具体日记用 - 无序列表，每条前面加 **YYYY-MM-DD**。
        - 关键判断、情绪词、建议结论 用 **加粗**。
        - 段落之间空一行。
        - 严禁用 "——" 连接段落（"——" 只用于列表项内 "日期 — 内容"）。
        - 严禁用 "第一...第二...第三..." 的连续段落，改为列表。
        - 中文全角标点（，。：；）。

        【Emoji — 适度使用】
        - ## 二级标题 前面加 1 个主题 emoji（如 📊 分析 / 💡 观察 / ⚠️ 风险 / ✅ 建议 / 🎯 重点）。
        - 关键情绪 / 数字结论前可用 1 个 emoji 点缀（😟 焦虑 / 😊 积极 / 📈 上升 / 📉 下降）。
        - 一段最多 1-2 个 emoji，避免堆砌；保持中文语境的克制感。

        【输出示例】
        ## 模式分析
        - **2026-04-28** — 凌晨 3 点仍醒着，反刍思维。
        - **2026-06-02** — mood 1/5，胃痛，出租车后座崩溃。

        ## 关键观察
        你的**反刍思维**和**躯体化**形成循环。
        """
    }

    // MARK: - Output post-processing
    //
    // The model is *asked* to use ## headers and - lists, but doesn't always
    // comply — Chinese-prose models often glue everything into a wall of text
    // separated by "——". This post-processor is a defensive pass: it splits
    // on the em-dash separators, bolds any YYYY-MM-DD dates, and turns any
    // remaining "。"-terminated sentence that contains a date into a list
    // item. Idempotent — safe to run on partial streaming content.

    private static let datePattern = #"(?<![\*])(\d{4}-\d{2}-\d{2})(?![\*])"#
    private static let listItemPattern = #"(?m)^[ \t]*[—\-•·][ \t]+"#
    private static let headerPattern = #"(?m)^#{1,6}[ \t]+"#

    // Heuristic regex set: each is a delimiter the model uses as a soft
    // "paragraph break" that the model never bothers to turn into a real
    // blank line. We convert them to `\n\n` so the new MarkdownText block
    // splitter gives them visible breathing room.
    private static let softSeparatorPatterns: [String] = [
        // 1. "——" (the most common em-dash separator) → blank line
        #"——"#,
        // 2. Chinese period followed by a new "topic" (a header char
        //    class or a date or an enumeration) → blank line. Skips
        //    short consecutive sentences to avoid splitting "你好。世界。"
        #"。(?=[一-鿿A-Z0-9*•\d])"#,
        // 3. Chinese comma directly before a YYYY-MM-DD date
        //    (e.g. "...胃痛,2026-06-02 胃痛...") → blank line
        #"，(?=\d{4}-\d{2}-\d{2})"#,
        // 4. "2." / "3." enumeration at sentence start (e.g. "——2. 运动驱动...")
        //    → blank line before the number
        #"(?<=[一-鿿。])\s*(\d+)\.\s"#,
    ]

    private func postProcess(_ s: String) -> String {
        var out = s
        for pattern in Self.softSeparatorPatterns {
            out = out.replacingOccurrences(
                of: pattern,
                with: "\n\n",
                options: .regularExpression
            )
        }
        // Collapse 3+ consecutive newlines into exactly two (keep
        // paragraph breaks clean).
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        // Bold any YYYY-MM-DD date that isn't already bolded.
        out = out.replacingOccurrences(
            of: Self.datePattern,
            with: "**$1**",
            options: .regularExpression
        )
        return out
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var thinkingExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            if message.role == .user { Spacer(minLength: 60) }
            if message.role == .assistant {
                Circle()
                    .fill(DS.Brand.amber.opacity(0.20))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(DS.Brand.amberDeep)
                    }
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant,
                   let thinking = message.thinking,
                   !thinking.isEmpty {
                    ThinkingDisclosure(
                        text: thinking,
                        isExpanded: $thinkingExpanded
                    )
                    .frame(maxWidth: 640, alignment: .leading)
                }
                Group {
                    if message.role == .user {
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        MarkdownText(markdown: message.content, baseFont: .body)
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.s + 2)
                // Semi-transparent bubbles. The user wanted them light
                // enough to feel like floating glass, not opaque cards.
                // User bubble: subtle amber tint, low opacity.
                // Assistant bubble: ultra-thin material on top of the
                // page background, no glass effect doubling it.
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                            .fill(DS.Brand.amber.opacity(0.20))
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                }
                .frame(maxWidth: 640, alignment: message.role == .user ? .trailing : .leading)
            }
            if message.role == .user {
                Circle()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

/// Collapsible card for `<think>...</think>` content. Collapsed by default.
struct ThinkingDisclosure: View {
    let text: String
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                Text("思考过程")
                    .font(.caption.weight(.medium))
                if !isExpanded {
                    Text("· \(text.count) 字符")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(.secondary.opacity(0.08))
        }
        .tint(.secondary)
    }
}
