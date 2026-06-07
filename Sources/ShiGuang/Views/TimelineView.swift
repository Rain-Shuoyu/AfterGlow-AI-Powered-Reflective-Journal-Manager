import SwiftUI

struct JournalView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var selectedEntry: DiaryEntry?

    /// Entries grouped by year-month, sorted newest-first.
    private var grouped: [(key: String, label: String, entries: [DiaryEntry])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy 年 M 月"
        let groups = Dictionary(grouping: store.entries) { e -> String in
            let c = cal.dateComponents([.year, .month], from: e.date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { (key, entries) in
                let label = df.string(from: entries.first?.date ?? Date())
                return (key, label, entries.sorted { $0.date > $1.date })
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                    .padding(.top, DS.Spacing.l)

                if store.folderURL == nil {
                    emptyState
                } else if store.isLoading {
                    ProgressView("正在扫描…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if store.entries.isEmpty {
                    noEntries
                } else {
                    LazyVStack(alignment: .leading, spacing: DS.Spacing.l) {
                        ForEach(grouped, id: \.key) { group in
                            MonthSection(
                                label: group.label,
                                count: group.entries.count,
                                entries: group.entries,
                                onTap: { selectedEntry = $0 }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .toolbar(.hidden)
        .sheet(item: $selectedEntry) { entry in
            DiaryDetailSheet(entry: entry)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("时间线").font(.largeTitle.weight(.semibold))
            if !store.entries.isEmpty {
                Text("\(store.stats.totalEntries) 篇日记 · \(formattedRange)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没选目录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formattedRange: String {
        guard let r = store.stats.dateRange else { return "" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "\(df.string(from: r.start)) → \(df.string(from: r.end))"
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.l) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("先到「统计」页选一个装满 .md 日记的目录。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var noEntries: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("目录里没找到 .md 文件")
            if let err = store.lastError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Month section

private struct MonthSection: View {
    let label: String
    let count: Int
    let entries: [DiaryEntry]
    let onTap: (DiaryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            // Month header
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                Text(label)
                    .font(.title3.weight(.semibold))
                Text("· \(count) 篇")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 70)   // align with card content (date col + dot col = 70)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    TimelineRow(
                        entry: entry,
                        isFirst: idx == 0,
                        isLast: idx == entries.count - 1,
                        onTap: { onTap(entry) }
                    )
                }
            }
        }
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let entry: DiaryEntry
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            // 1. Date column (fixed width)
            VStack(spacing: 2) {
                Text(dayString)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(weekdayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .trailing)
            .padding(.top, 18)

            // 2. Timeline rail (dot + line)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2, height: 18)
                    .opacity(isFirst ? 0 : 1)
                Circle()
                    .fill(moodColor)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().stroke(.background, lineWidth: 3)
                    }
                    .shadow(color: moodColor.opacity(0.5), radius: 4, y: 0)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 18)

            // 3. Card
            card
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(2)
            if !entry.preview.isEmpty {
                Text(entry.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: DS.Spacing.s) {
                if let m = entry.frontmatter.mood {
                    HStack(spacing: 4) {
                        Circle().fill(moodColor).frame(width: 6, height: 6)
                        Text("mood \(m)/5").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !entry.frontmatter.tags.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.frontmatter.tags.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let wc = entry.wordCount > 0 ? entry.wordCount : nil {
                    Spacer()
                    Text("\(wc) 字")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(DS.Spacing.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .strokeBorder(hovering ? Color.accentColor.opacity(0.5) : .white.opacity(0.05), lineWidth: 1)
        }
        .scaleEffect(hovering ? 1.01 : 1.0)
        .padding(.bottom, DS.Spacing.s)
    }

    private var dayString: String {
        let df = DateFormatter()
        df.dateFormat = "M-d"
        return df.string(from: entry.date)
    }

    private var weekdayString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "EEE"
        return df.string(from: entry.date)
    }

    private var moodColor: Color {
        switch entry.frontmatter.mood {
        case 1: return .red
        case 2: return .orange
        case 3: return .gray
        case 4: return .green
        case 5: return .mint
        default: return .accentColor
        }
    }
}

// MARK: - Detail sheet

struct DiaryDetailSheet: View {
    let entry: DiaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    MarkdownText(markdown: entry.rawContent, baseFont: .body)
                }
                .padding(DS.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Text(entry.date.short)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let m = entry.frontmatter.mood {
                    HStack(spacing: 4) {
                        Circle().fill(moodColor(m)).frame(width: 8, height: 8)
                        Text("mood \(m)/5").font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(moodColor(m).opacity(0.15)))
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
            Text(entry.title)
                .font(.largeTitle.weight(.semibold))
            if !entry.frontmatter.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.frontmatter.tags, id: \.self) { t in
                        Text(t)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.tint.opacity(0.12)))
                    }
                }
            }
        }
        .padding(DS.Spacing.l)
    }

    private func moodColor(_ id: Int) -> Color {
        switch id {
        case 1: return .red
        case 2: return .orange
        case 3: return .gray
        case 4: return .green
        case 5: return .mint
        default: return .accentColor
        }
    }
}
