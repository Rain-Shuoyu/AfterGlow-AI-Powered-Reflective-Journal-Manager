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
                        GlassEffectContainer(spacing: DS.Spacing.m) {
                            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                                ForEach(messages.dropFirst()) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                }
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
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            SectionTitle("试着问我", subtitle: "点一下就发送")
            FlowLayout(spacing: DS.Spacing.s) {
                ForEach(suggestedQuestions, id: \.self) { q in
                    Button {
                        send(q)
                    } label: {
                        Text(q)
                            .font(.callout)
                            .padding(.horizontal, DS.Spacing.m)
                            .padding(.vertical, DS.Spacing.s + 2)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.s) {
            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.s)
                .frame(minHeight: 40, maxHeight: 140)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .fill(.regularMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            Button {
                send(input)
                input = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.callout.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(DS.Brand.amber)
                            .squircle(DS.Radius.pill)
                    }
                    .foregroundStyle(DS.Brand.ink)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isAsking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DS.Spacing.l)
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
        """
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
                // Collapsible thinking block — only for assistant, only when there's content.
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
                .background {
                    Group {
                        if message.role == .user {
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .fill(DS.Brand.amber.opacity(0.32))
                        } else {
                            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l, style: .continuous))
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
