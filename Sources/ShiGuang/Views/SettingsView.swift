import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var updateStore: UpdateStore
    @EnvironmentObject var practiceStore: DailyPracticeStore
    @EnvironmentObject var anniversaryStore: AnniversaryStore
    @EnvironmentObject var rescueStore: RescueStore
    @State private var questionService: SelfQuestionService?
    @State private var testing: Bool = false
    @State private var testResult: String?
    @State private var showApiKey: Bool = false
    @State private var confirmResetStreaks: Bool = false
    @State private var confirmToggleAnniversary: Bool = false
    @State private var confirmToggleRescue: Bool = false
    @State private var confirmToggleSelfQuestion: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                sectionCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "更新",
                    subtitle: "v\(UpdateChecker.currentVersion)"
                ) {
                    updateRows
                }
                sectionCard(
                    icon: "folder.fill",
                    title: "日记目录",
                    subtitle: "选一次记住，下次启动自动恢复"
                ) {
                    diaryFolderRow
                }

                sectionCard(
                    icon: "cpu.fill",
                    title: "AI 提供方",
                    subtitle: providerSubtitle
                ) {
                    providerRows
                }

                sectionCard(
                    icon: "slider.horizontal.3",
                    title: "检索",
                    subtitle: "控制 LLM 看到的上下文"
                ) {
                    retrievalRows
                }

                sectionCard(
                    icon: "text.bubble.fill",
                    title: "系统提示词",
                    subtitle: "可选，会拼到默认 prompt 之后"
                ) {
                    systemPromptEditor
                }

                sectionCard(
                    icon: "sparkles",
                    title: "仪式感",
                    subtitle: "每日签 / 周年 / 急救 的状态与控制"
                ) {
                    ritualRows
                }

                sectionCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "危险操作",
                    subtitle: nil,
                    tint: .red
                ) {
                    resetRow
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.l)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity)
        .navigationTitle("")
        .toolbar(.hidden)
        .onAppear {
            if questionService == nil {
                questionService = SelfQuestionService(settingsStore: settingsStore)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.system(size: 28, weight: .semibold))
            Text("只需要填 API Key，其他都是默认")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, DS.Spacing.s)
    }

    // MARK: - Section card

    /// A consistent card wrapper for every settings group. Each card
    /// has a header row (icon + title + optional subtitle) and a body
    /// with the actual rows. `tint` lets the danger card use red.
    @ViewBuilder
    private func sectionCard<Content: View>(
        icon: String,
        title: String,
        subtitle: String?,
        tint: Color = DS.Brand.amber,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip — icon + title left, subtitle right
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(title)
                    .font(.callout.weight(.semibold))
                if let s = subtitle {
                    Spacer()
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.s)

            Divider()
                .padding(.horizontal, DS.Spacing.m)

            // Body
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                content()
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.m)
        }
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        }
    }

    // MARK: - Diary folder

    private var diaryFolderRow: some View {
        row {
            Image(systemName: "folder.fill")
                .foregroundStyle(DS.Brand.amber)
            Text(store.folderURL?.path ?? "未选择")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(store.folderURL == nil ? .secondary : .primary)
            Spacer()
            Button {
                store.pickFolder()
            } label: {
                Text("选择…")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    // MARK: - Update

    private var updateRows: some View {
        // State is held in the shared `UpdateStore` so the launch
        // screen can kick off the check on startup and the result
        // is already populated by the time the user lands here.
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(updateStatusText)
                    .font(.callout)
                    .foregroundStyle(updateStatusColor)
                Spacer()
                if updateStore.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        updateStore.check()
                    } label: {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.Brand.amber)
                }
            }
            if case .updateAvailable(_, let latest, let url) = updateStore.status {
                HStack {
                    Text("新版本 v\(latest) 已发布")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Link(destination: url) {
                        Label("前往下载", systemImage: "arrow.up.right.square")
                            .font(.callout)
                    }
                }
            }
            // Sub-line: when did the last *automatic* check happen?
            // Manual checks bypass the 12h throttle, so this
            // timestamp only reflects what the launch screen did.
            if let when = updateStore.lastAutomaticCheckDescription {
                Text(when)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var updateStatusText: String {
        switch updateStore.status {
        case .none:
            return "当前版本 v\(updateStore.currentVersion)"
        case .checking:
            return "正在检查…"
        case .upToDate(let current, let latest):
            // Two "up to date" sub-cases that mean different things:
            //   current == latest  →  everything is in sync
            //   current  > latest  →  local is *ahead* of what's
            //                         published (newer dev build,
            //                         or release not pushed yet)
            if current == latest {
                return "已是最新 v\(current)"
            } else {
                return "本地 v\(current) 比最新发布 v\(latest) 更新"
            }
        case .updateAvailable(let current, let latest, _):
            return "v\(current) → v\(latest) 可更新"
        case .error(let msg):
            return msg
        }
    }

    private var updateStatusColor: Color {
        switch updateStore.status {
        case .none:            return .secondary
        case .checking:        return .secondary
        case .upToDate:        return .green
        case .updateAvailable: return DS.Brand.amber
        case .error:           return .secondary
        }
    }

    // MARK: - Provider

    private var providerSubtitle: String {
        switch settingsStore.settings.provider {
        case .minimax: return "MiniMax 官方 (M2.7)"
        case .openAI:  return "OpenAI 兼容"
        case .anthropic: return "Anthropic Messages"
        }
    }

    private var providerRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 协议
            labelledRow("协议") {
                Picker("", selection: $settingsStore.settings.provider) {
                    ForEach(AppSettings.LLMProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: settingsStore.settings.provider) { newValue in
                    let d = AppSettings.defaults(for: newValue)
                    settingsStore.settings.baseURL = d.baseURL
                    settingsStore.settings.model = d.model
                }
            }

            // Base URL + 重置
            labelledRow("Base URL") {
                TextField("", text: $settingsStore.settings.baseURL)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 320)
                    .onSubmit { /* live binding */ }
                Button {
                    let d = AppSettings.defaults(for: settingsStore.settings.provider)
                    settingsStore.settings.baseURL = d.baseURL
                    settingsStore.settings.model = d.model
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("恢复当前协议的官方端点")
            }

            // Model
            labelledRow("Model") {
                TextField("", text: $settingsStore.settings.model)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)
            }

            // API Key + 显示/隐藏 + 测试
            labelledRow("API Key") {
                Group {
                    if showApiKey {
                        TextField("", text: $settingsStore.settings.apiKey)
                    } else {
                        SecureField("", text: $settingsStore.settings.apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .frame(maxWidth: 280)
                .overlay(alignment: .trailing) {
                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .help(showApiKey ? "隐藏" : "显示")
                }

                Button {
                    Task { await runTest() }
                } label: {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("测试", systemImage: "bolt.horizontal")
                            .font(.callout)
                    }
                }
                .buttonStyle(.bordered)
                .tint(DS.Brand.amber)
                .disabled(testing || settingsStore.settings.apiKey.isEmpty)
            }

            // 测试结果 + provider 提示（同一行，节省垂直空间）
            if let r = testResult {
                HStack(spacing: 6) {
                    Image(systemName: r.hasPrefix("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testResultColor)
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(testResultColor)
                }
            } else if settingsStore.settings.provider == .minimax {
                Text("在 platform.minimaxi.com 的「接口密钥」页生成 API Key")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Retrieval

    private var retrievalRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelledRow("上下文篇数") {
                Stepper("",
                        value: $settingsStore.settings.maxContextEntries,
                        in: 5...200, step: 5)
                    .labelsHidden()
                Text("\(settingsStore.settings.maxContextEntries)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            labelledRow("Temperature") {
                Slider(value: $settingsStore.settings.temperature, in: 0...1, step: 0.05)
                    .frame(width: 220)
                Text(String(format: "%.2f", settingsStore.settings.temperature))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - System prompt

    private var systemPromptEditor: some View {
        TextEditor(text: $settingsStore.settings.systemPromptAddition)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 90)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            }
    }

    // MARK: - Reset

    private var resetRow: some View {
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("恢复所有设置到默认值")
                    .foregroundStyle(.primary)
                Text("重置日记目录、API Key、模型、检索参数")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive) {
                settingsStore.reset()
                testResult = nil
            } label: {
                Text("恢复默认")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - 仪式感

    /// "仪式感" settings — streak / banner toggles. All four
    /// rows are toggles/buttons that drive the per-feature
    /// stores directly. No LLM cost, no settings persisted in
    /// `AppSettings` — they live in the per-feature UserDefaults
    /// namespaces and are owned by their respective stores.
    @ViewBuilder
    private var ritualRows: some View {
        // ── 今日签 streak ───────────────────────────────────
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日签")
                    .foregroundStyle(.primary)
                Text("当前 \(practiceStore.streak) 天 · 最长 \(practiceStore.longestStreak) 天 · 跳过不扣分")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive) {
                confirmResetStreaks = true
            } label: {
                Text("重置 streak")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(practiceStore.streak == 0 && practiceStore.longestStreak == 0)
        }
        Divider().opacity(0.3)

        // ── 周年 banner ─────────────────────────────────────
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("周年回响 banner")
                    .foregroundStyle(.primary)
                Text(anniversaryStore.isUserDisabled
                     ? "已关闭。往年的今天不会再主动提醒。"
                     : "6/15 ±1 天内自动出现。可关闭。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !anniversaryStore.isUserDisabled },
                set: { newValue in
                    if !newValue {
                        // Going from on→off, ask first.
                        confirmToggleAnniversary = true
                    } else {
                        anniversaryStore.setUserDisabled(false)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        Divider().opacity(0.3)

        // ── 急救 banner ──────────────────────────────────────
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("情绪急救 banner")
                    .foregroundStyle(.primary)
                Text(rescueStore.isUserDisabled
                     ? "已关闭。连续 3 天情绪低时不会再主动浮现。"
                     : "检测到连续 3 天情绪低 + 关键词时浮现。可关闭。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !rescueStore.isUserDisabled },
                set: { newValue in
                    if !newValue {
                        confirmToggleRescue = true
                    } else {
                        rescueStore.setUserDisabled(false)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        Divider().opacity(0.3)

        // ── 自我追问 card ─────────────────────────────────────
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("自我追问")
                    .foregroundStyle(.primary)
                Text((questionService?.isUserDisabled ?? false)
                     ? "已关闭。写作 tab 顶部不再展示 AI 提取的问题。"
                     : "每月 1 次，AI 从你的日记里提取悬而未决的问题。可关闭。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !(questionService?.isUserDisabled ?? false) },
                set: { newValue in
                    if !newValue {
                        confirmToggleSelfQuestion = true
                    } else {
                        questionService?.setUserDisabled(false)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }

        // ── Confirms ─────────────────────────────────────────
        .alert("重置今日签 streak？", isPresented: $confirmResetStreaks) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                practiceStore.resetStreaks()
            }
        } message: {
            Text("当前连续天数和最长记录都会清零。不可撤销。")
        }
        .alert("关闭周年 banner？", isPresented: $confirmToggleAnniversary) {
            Button("取消", role: .cancel) {}
            Button("关闭", role: .destructive) {
                anniversaryStore.setUserDisabled(true)
            }
        } message: {
            Text("你可以在这个开关处随时重新打开。")
        }
        .alert("关闭情绪急救 banner？", isPresented: $confirmToggleRescue) {
            Button("取消", role: .cancel) {}
            Button("关闭", role: .destructive) {
                rescueStore.setUserDisabled(true)
            }
        } message: {
            Text("你可以在这个开关处随时重新打开。")
        }
        .alert("关闭自我追问？", isPresented: $confirmToggleSelfQuestion) {
            Button("取消", role: .cancel) {}
            Button("关闭", role: .destructive) {
                questionService?.setUserDisabled(true)
            }
        } message: {
            Text("写作 tab 顶部的 待回答 卡片会变成「已关闭」状态。你可以在这个开关处随时重新打开。")
        }
    }

    // MARK: - Row helpers

    /// A two-column row: `label` on the left (fixed width), `content`
    /// on the right (flexible, trailing-aligned). Used inside every
    /// section card to keep the alignment consistent.
    @ViewBuilder
    private func labelledRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// A two-column row with no leading label, for custom content
    /// (folder path, reset button, etc.).
    @ViewBuilder
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            content()
        }
    }

    // MARK: - Test

    private var testResultColor: Color {
        guard let r = testResult else { return .secondary }
        if r.hasPrefix("✅") { return .green }
        if r.hasPrefix("❌") { return .red }
        return .secondary
    }

    @MainActor
    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let client = try LLMClientFactory.make(settings: settingsStore.settings)
            let req = ChatRequest(
                messages: [
                    ChatMessage(role: .system, content: "你是测试桩。回答一个字：OK。"),
                    ChatMessage(role: .user, content: "ping")
                ],
                model: settingsStore.settings.model,
                temperature: 0
            )
            let resp = try await client.chat(req)
            testResult = "✅ 连接成功。模型回复：\(resp.text.prefix(60))"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}
