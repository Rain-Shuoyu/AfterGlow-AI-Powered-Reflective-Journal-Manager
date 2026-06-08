import SwiftUI

/// The "Insight" tab container. Switches between a linear timeline view and
/// an Obsidian-style entity graph view via a top-left segmented control.
struct InsightView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore

    enum Mode: String, CaseIterable, Identifiable {
        case timeline = "时间线"
        case graph    = "关系图"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .timeline: return "list.bullet.indent"
            case .graph:    return "circle.grid.cross"
            }
        }
    }

    @State private var mode: Mode = .timeline
    @State private var selectedEntry: DiaryEntry?
    /// When non-nil, the "回溯" sheet is shown for this entry.
    @State private var flashbackEntry: DiaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top-left view switcher + 回溯
            HStack(alignment: .center, spacing: DS.Spacing.m) {
                ModePicker(mode: $mode)
                Spacer()
                flashbackButton
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)

            // Content
            Group {
                switch mode {
                case .timeline:
                    InsightTimelineView()
                case .graph:
                    InsightGraphView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $selectedEntry) { entry in
            DiaryDetailSheet(entry: entry)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
        .sheet(item: $flashbackEntry) { entry in
            FlashbackSheet(entry: entry, settings: settingsStore.settings)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
        // The sub-views own their own headers; make sure no top inset lingers.
        .navigationTitle("")
        .toolbar(.hidden)
    }

    /// "🪄 回溯" button in the Insight header. Picks a random
    /// entry from the loaded set and opens `FlashbackSheet` for
    /// it. Disabled when:
    ///   - no entries (nothing to flash back to)
    ///   - no API key (LLM call would fail immediately)
    private var flashbackButton: some View {
        Button {
            if let pick = FlashbackSheet.pickRandom(from: store.entries) {
                flashbackEntry = pick
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                Text("回溯")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Brand.amber.opacity(0.20))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.5), lineWidth: 0.8)
            }
            .foregroundStyle(DS.Brand.amberDeep)
        }
        .buttonStyle(.plain)
        .disabled(
            store.entries.isEmpty
            || settingsStore.settings.apiKey.isEmpty
        )
        .help(
            store.entries.isEmpty
                ? "选个日记目录，先有几篇日记才能回溯"
                : (settingsStore.settings.apiKey.isEmpty
                    ? "先到设置填 API Key"
                    : "随机挑一篇过去的日记，AI 帮你回顾那天")
        )
    }
}

// MARK: - Mode picker (segmented, top-left)

struct ModePicker: View {
    @Binding var mode: InsightView.Mode
    var body: some View {
        HStack(spacing: 0) {
            ForEach(InsightView.Mode.allCases) { m in
                let isActive = m == mode
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mode = m }
                } label: {
            HStack(spacing: 5) {
                Image(systemName: m.systemImage)
                    .font(.caption)
                Text(m.rawValue)
                    .font(.callout.weight(isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? DS.Brand.ink : .primary)
            .background {
                if isActive {
                    Capsule(style: .continuous).fill(DS.Brand.amber)
                }
            }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}
