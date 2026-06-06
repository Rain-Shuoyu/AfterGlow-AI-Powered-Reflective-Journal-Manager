import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var testing: Bool = false
    @State private var testResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置").font(.largeTitle.weight(.semibold))
                    Text("只需要填 API Key，其他都是默认").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, DS.Spacing.l)

                Section {
                    diaryFolderRow
                } header: {
                    SectionTitle("日记目录")
                }

                Section {
                    providerSection
                } header: {
                    SectionTitle("LLM 提供方")
                }

                Section {
                    retrievalSection
                } header: {
                    SectionTitle("检索")
                }

                Section {
                    systemPromptSection
                } header: {
                    SectionTitle("自定义系统提示词", subtitle: "可选，会拼到默认 prompt 之后")
                }

                Section {
                    resetButton
                } header: {
                    SectionTitle("危险操作")
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xxl)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity)
        .navigationTitle("")
        .toolbar(.hidden)
    }

    // MARK: - Diary folder

    private var diaryFolderRow: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
            Text(settingsStore.settings.diaryFolderPath ?? "未选择")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LiquidButton("选择…", systemImage: nil) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    settingsStore.settings.diaryFolderPath = url.path
                }
            }
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("协议").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $settingsStore.settings.provider) {
                    ForEach(AppSettings.LLMProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: settingsStore.settings.provider) { newValue in
                    let defaults = AppSettings.defaults(for: newValue)
                    settingsStore.settings.baseURL = defaults.baseURL
                    settingsStore.settings.model = defaults.model
                }
            }
            fieldRow(label: "Base URL", text: $settingsStore.settings.baseURL, secure: false)
            fieldRow(label: "Model", text: $settingsStore.settings.model, secure: false)
            fieldRow(label: "API Key", text: $settingsStore.settings.apiKey, secure: true)
            HStack {
                if let r = testResult {
                    Text(r).font(.caption).foregroundStyle(testResultColor)
                }
                Spacer()
                LiquidButton(testing ? "测试中…" : "测试连接", systemImage: testing ? nil : "bolt.horizontal") {
                    Task { await runTest() }
                }
                .disabled(testing || settingsStore.settings.apiKey.isEmpty)
            }
            if settingsStore.settings.provider == .minimax {
                Text("MiniMax 官方公开 API，OpenAI Chat Completions 协议。\n在 platform.minimaxi.com 的「接口密钥」页生成 API Key，充值后即可调用。默认模型 MiniMax-M2.7。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(DS.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .fill(.tint.opacity(0.10))
                    }
            }
        }
    }

    private func fieldRow(label: String, text: Binding<String>, secure: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }

    // MARK: - Retrieval

    private var retrievalSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("每次送 LLM 的篇数").foregroundStyle(.secondary)
                Spacer()
                Stepper("",
                        value: $settingsStore.settings.maxContextEntries,
                        in: 5...200, step: 5)
                    .labelsHidden()
                Text("\(settingsStore.settings.maxContextEntries)")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            HStack {
                Text("Temperature").foregroundStyle(.secondary)
                Slider(value: $settingsStore.settings.temperature, in: 0...1, step: 0.05)
                Text(String(format: "%.2f", settingsStore.settings.temperature))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - System prompt

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            TextEditor(text: $settingsStore.settings.systemPromptAddition)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.s)
                .frame(minHeight: 100)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(.regularMaterial)
                }
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        HStack {
            Text("恢复所有设置到默认值").foregroundStyle(.secondary)
            Spacer()
            LiquidButton("恢复默认", systemImage: nil, role: .destructive) {
                settingsStore.reset()
                testResult = nil
            }
        }
    }

    private var testResultColor: Color {
        if let r = testResult {
            if r.hasPrefix("✅") { return .green }
            if r.hasPrefix("❌") { return .red }
        }
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
