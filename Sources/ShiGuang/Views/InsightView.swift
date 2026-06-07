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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top-left view switcher + refresh
            HStack(alignment: .center, spacing: DS.Spacing.m) {
                ModePicker(mode: $mode)
                Spacer()
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
        // The sub-views own their own headers; make sure no top inset lingers.
        .navigationTitle("")
        .toolbar(.hidden)
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
                    .foregroundStyle(isActive ? .white : .primary)
                    .background {
                        if isActive {
                            Capsule(style: .continuous).fill(.tint)
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
