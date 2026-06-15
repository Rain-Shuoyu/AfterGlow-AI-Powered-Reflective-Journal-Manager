import SwiftUI

/// The "写作" tab. Two-state screen:
///   - List state (default): shows recent entries (newest first) +
///     a prominent "+ 新建今日" button at the top. Tapping an entry
///     opens the editor pre-loaded from that file.
///   - Sheet state: presents the editor as a `.sheet(item:)` floating
///     modal, matching the visual treatment of the Insight preview
///     sheet (`.regularMaterial` card on top of the same backdrop).
struct EditorTabView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    /// `nil` until first onAppear, then a real service. We
    /// can't construct the service in `init` because it needs
    /// the env-object settings store.
    @State private var questionService: SelfQuestionService?

    @State private var sheetItem: EditorSheetItem? = nil
    @State private var confirmDelete: DiaryEntry? = nil
    @State private var showTrash: Bool = false
    @State private var showLetterChoice: Bool = false
    @State private var showMoodQuick: Bool = false
    /// When set, the letter-writing sheet is presented for this scenario.
    @State private var letterScenario: LetterPrompt.Scenario?

    var body: some View {
        // Plain list (no ZStack needed — the sheet is system-managed).
        listView
            .sheet(item: $sheetItem) { item in
                EditorView(state: item.state) {
                    sheetItem = nil
                }
                .frame(idealWidth: 820, idealHeight: 720)
            }
            .sheet(isPresented: $showTrash) {
                TrashView(
                    trash: DiaryTrash.shared,
                    restoreFolder: store.folderURL
                ) {
                    // After trash is closed, the active diary list may
                    // have changed (a restore added a new file). Re-scan
                    // so the user sees it in the list without a manual
                    // refresh.
                    showTrash = false
                    store.reload()
                }
            }
            .sheet(isPresented: $showLetterChoice) {
                LetterChoiceSheet { scenario in
                    showLetterChoice = false
                    // Defer to next runloop so the choice sheet
                    // dismisses before the letter sheet opens.
                    DispatchQueue.main.async {
                        letterScenario = scenario
                    }
                }
            }
            .sheet(item: $letterScenario) { scenario in
                LetterEditorSheet(
                    scenario: scenario,
                    settingsStore: settingsStore
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showMoodQuick) {
                MoodQuickSheet()
                    .environmentObject(store)
            }
            .onAppear {
                if questionService == nil {
                    questionService = SelfQuestionService(settingsStore: settingsStore)
                }
            }
    }

    // MARK: - List

    private var listView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("写作")
                        .font(.title2.weight(.semibold))
                    Text("\(store.entries.count) 篇")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showTrash = true
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("回收站")
                if let url = store.folderURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(url.path)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.s)

            newEntryButton
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.m)

            letterCard
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.m)

            moodQuickCard
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.m)

            if let service = questionService {
                SelfQuestionCard(service: service)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.bottom, DS.Spacing.m)
            }

            if store.entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedEntries, id: \.month) { group in
                        Section(group.month) {
                            ForEach(group.entries) { entry in
                                entryRow(entry)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            confirmDelete = entry
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .alert("删除日记？", isPresented: .constant(confirmDelete != nil)) {
            Button("取消", role: .cancel) { confirmDelete = nil }
            Button("删除", role: .destructive) {
                if let e = confirmDelete {
                    store.delete(entry: e)
                }
                confirmDelete = nil
            }
        } message: {
            Text("将永久删除该 Markdown 文件，操作不可撤销。")
        }
    }

    private var newEntryButton: some View {
        Button {
            sheetItem = EditorSheetItem(state: .forNewEntry())
        } label: {
            HStack {
                Image(systemName: "plus")
                Text("新建今日")
            }
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Brand.amber)
            }
            .foregroundStyle(.white)
            .shadow(color: DS.Brand.amber.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }

    /// "🪞 写一封信" entry-point card. Sits right under the
    /// "新建今日" button. Tapping it opens `LetterChoiceSheet`
    /// where the user picks a scenario, after which the editor
    /// sheet opens pre-filled with the LLM-generated opening.
    private var letterCard: some View {
        Button {
            showLetterChoice = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(DS.Brand.amber.opacity(0.15))
                    Text("🪞")
                        .font(.system(size: 22))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("写一封信")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("给自己，或给重要的人。AI 只起头，主体由你写。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.20), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("✍️ 现在写一封：5 种提示信，AI 帮你起头")
        .disabled(store.folderURL == nil)
        .opacity(store.folderURL == nil ? 0.5 : 1)
    }

    /// "🌧 1 行情绪" compact card. Sits below the letter
    /// card. If the user has already logged today, show the
    /// logged value as a static pill; otherwise prompt them to
    /// record one.
    private var moodQuickCard: some View {
        Button {
            showMoodQuick = true
        } label: {
            HStack(spacing: 10) {
                Text(todayMoodQuick?.emoji ?? "🌧")
                    .font(.system(size: 18))
                if let mq = todayMoodQuick {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("今天: \(mq.text.isEmpty ? "已记" : mq.text)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("点击修改")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("1 行情绪")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("用 1 秒钟记下现在感觉")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        todayMoodQuick != nil
                            ? DS.Brand.amber.opacity(0.30)
                            : Color.white.opacity(0.05),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .help("🌧 1 行情绪：4 个 emoji + 60 字内")
    }

    /// Today's logged mood_quick (if any). Used by the card to
    /// show the "已记" pill state.
    private var todayMoodQuick: MoodQuick? {
        guard let entry = store.entries.first(where: {
            Calendar.current.isDateInToday($0.date)
        }) else { return nil }
        return RescueDetector.parseMoodQuick(from: entry)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有日记")
                .font(.headline)
            Text(store.folderURL == nil
                 ? "请在「设置」里选择一个文件夹后开始记录。"
                 : "点击上方「新建今日」开始记录你的第一篇。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xl)
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        Button {
            sheetItem = EditorSheetItem(state: .from(entry: entry))
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.s) {
                VStack(spacing: 0) {
                    Text(dayNumber(entry.date))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(DS.Brand.amber)
                    Text(weekday(entry.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if let mood = entry.frontmatter.mood {
                            moodPill(mood)
                        }
                    }
                    Text(entry.preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !entry.frontmatter.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(entry.frontmatter.tags.prefix(4), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Brand.amber)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func moodPill(_ v: Int) -> some View {
        let labels = ["", "很差", "差", "一般", "好", "很好"]
        return Text(labels[v])
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(.secondary.opacity(0.15))
            }
    }

    // MARK: - Grouping helpers

    private struct GroupedEntries { let month: String; let entries: [DiaryEntry] }

    private var groupedEntries: [GroupedEntries] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy 年 M 月"
        let groups = Dictionary(grouping: store.entries) { fmt.string(from: $0.date) }
        return groups
            .map { GroupedEntries(month: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { lhs, rhs in
                (lhs.entries.first?.date ?? .distantPast) > (rhs.entries.first?.date ?? .distantPast)
            }
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

/// Wrapper for `.sheet(item:)` — `EditorState` itself isn't `Identifiable`,
/// so we wrap it with a UUID-keyed shell that also doubles as the diff key
/// when SwiftUI re-presents the sheet for a different entry.
struct EditorSheetItem: Identifiable {
    let id = UUID()
    var state: EditorState
}
