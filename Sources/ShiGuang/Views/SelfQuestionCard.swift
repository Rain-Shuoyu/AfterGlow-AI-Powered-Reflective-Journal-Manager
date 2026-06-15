import SwiftUI

/// "📓 待回答" card shown at the top of the 写作 tab.
///
/// Shows up to 3 questions at a time. Tapping "→ 写一写" opens
/// the editor pre-filled with the question. Tapping "跳过"
/// removes the question from the visible list (cache is
/// regenerated on next refresh).
struct SelfQuestionCard: View {

    @EnvironmentObject var diaryStore: DiaryStore
    @ObservedObject var service: SelfQuestionService
    @EnvironmentObject var settingsStore: SettingsStore

    // No explicit init — both env objects come from the parent.

    @State private var showEditor: EditorSheetItem?
    @State private var selectedEntry: DiaryEntry?
    @State private var showNoKeyHint: Bool = false

    var body: some View {
        cardContent
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.18), lineWidth: 0.5)
            }
            .sheet(item: $showEditor) { item in
                EditorView(state: item.state) {
                    showEditor = nil
                }
                .frame(idealWidth: 820, idealHeight: 720)
            }
            .sheet(item: $selectedEntry) { entry in
                DiaryDetailSheet(entry: entry)
                    .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
            }
            .onAppear {
                // Trigger a refresh if the cache is stale. The
                // service is silent if the cache is fresh.
                service.cachedOrRefresh(entries: diaryStore.entries)
            }
            .onChange(of: diaryStore.entries) { _, _ in
                service.cachedOrRefresh(entries: diaryStore.entries)
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if service.isUserDisabled {
                disabledState
            } else if service.questions.isEmpty {
                emptyOrLoading
            } else {
                ForEach(service.questions.prefix(3)) { q in
                    questionRow(q)
                }
                if service.questions.count > 3 {
                    Text("…还有 \(service.questions.count - 3) 个待回答")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("📓")
                .font(.system(size: 16))
            Text("待回答")
                .font(.callout.weight(.semibold))
            Spacer()
            if service.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("重新跑 AI…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Question row

    private func questionRow(_ q: SelfQuestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            kindBadge(q.kind)
            VStack(alignment: .leading, spacing: 6) {
                Text(q.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        handleWrite(q)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                            Text("写一写")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(DS.Brand.amber)
                    }
                    .buttonStyle(.plain)
                    Button {
                        service.dismissQuestion(q.id)
                    } label: {
                        Text("跳过")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    if let date = q.sourceDate,
                       let entry = diaryStore.entries.first(where: { Calendar.current.isDate(date, inSameDayAs: $0.date) })
                    {
                        Button {
                            selectedEntry = entry
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("看那天")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func kindBadge(_ k: SelfQuestion.Kind) -> some View {
        let (icon, color): (String, Color) = {
            switch k {
            case .unresolved: return ("questionmark.bubble", DS.Brand.amber)
            case .definition: return ("text.book.closed", .blue.opacity(0.7))
            case .emotion:    return ("heart", .pink.opacity(0.7))
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(color.opacity(0.12))
            )
    }

    // MARK: - Empty / loading

    /// Static "已关闭" state shown when the user has toggled
    /// self-question generation off in Settings. No question
    /// rows, no "换一批" button — just a quiet reminder that
    /// the feature exists but is paused.
    private var disabledState: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("自我追问已关闭。设置 → 仪式感 可重新打开。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var emptyOrLoading: some View {
        Group {
            if service.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("AI 正在从你过去的日记里找问题…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if settingsStore.settings.apiKey.isEmpty {
                Text("填了 API Key 才能让 AI 帮你找问题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let err = service.lastError, !err.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("出错：\(err)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("点下面的 换一批 重试。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                Text(service.questions.isEmpty
                     ? "暂时没找到可以追问的——可能日记还不够多。"
                     : "全部跳过了")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !service.isUserDisabled, let last = service.lastRefreshed {
                Text("上次更新: \(relativeDate(last))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await service.refresh(entries: diaryStore.entries) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("换一批")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(DS.Brand.amber)
            }
            .buttonStyle(.plain)
            .disabled(service.isUserDisabled
                      || service.isRefreshing
                      || settingsStore.settings.apiKey.isEmpty)
        }
    }

    // MARK: - Actions

    private func handleWrite(_ q: SelfQuestion) {
        // Pre-fill the editor with the question in a callout
        // block. User writes the body — same principle as
        // letters: LLM only sets the frame.
        let state = EditorState.forQuestion(q)
        showEditor = EditorSheetItem(state: state)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f.localizedString(for: d, relativeTo: Date())
    }
}
