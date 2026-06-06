import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                header
                    .padding(.top, DS.Spacing.l)

                if store.folderURL == nil {
                    emptyState
                } else if store.isLoading {
                    loadingState
                } else if store.entries.isEmpty {
                    noEntries
                } else {
                    statStrip
                    heatmap
                    trend
                    moodAndTags
                    recentEntries
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .toolbar(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("日记洞察")
                    .font(.largeTitle.weight(.semibold))
                Text(store.folderURL?.path ?? "还没选目录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            LiquidButton("选择目录", systemImage: "folder") {
                store.pickFolder()
            }
            LiquidButton("刷新", systemImage: "arrow.clockwise") {
                store.reload()
            }
            .disabled(store.folderURL == nil)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.l) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("点上面的「选择目录」按钮，挑一个装满 .md 日记的文件夹就行。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在扫描…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
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

    // MARK: - Stat strip (single horizontal bar, no grid of cards)

    private var statStrip: some View {
        // Note: keep NO background/clipping on the ScrollView itself — the
        // default scroller background shows up as a translucent rectangle
        // on macOS and we want the glass pills to float on the window backdrop.
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: DS.Spacing.m) {
                HStack(spacing: DS.Spacing.m) {
                    StatPill(label: "总日记数", value: "\(store.stats.totalEntries)", systemImage: "doc.text")
                    StatPill(label: "总字数", value: store.stats.totalWords.formatted(), systemImage: "textformat")
                    StatPill(label: "平均每篇", value: String(format: "%.0f", store.stats.averageWordsPerEntry), systemImage: "chart.bar")
                    StatPill(label: "最长连续", value: "\(store.stats.writingStreakDays) 天", systemImage: "flame", tint: .orange)
                    StatPill(label: "当前连续", value: "\(store.stats.currentStreakDays) 天", systemImage: "calendar.badge.checkmark", tint: .green)
                    if let r = store.stats.dateRange {
                        let days = (Calendar.current.dateComponents([.day], from: r.start, to: r.end).day ?? 0) + 1
                        StatPill(label: "覆盖天数", value: "\(days)", systemImage: "calendar")
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color.clear)
    }

    // MARK: - Heatmap (no card, just sits in the flow)

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            SectionTitle("字数热力图", subtitle: "过去 52 周")
            ScrollView(.horizontal, showsIndicators: false) {
                HeatmapView(metrics: store.stats.dailyWordCounts)
            }
        }
    }

    // MARK: - Trend

    private var trend: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            SectionTitle("月度趋势", subtitle: "柱 = 字数；折线 = 平均情绪（×1000）")
            TrendChartView(monthly: store.stats.monthlyWordCounts)
                .padding(.top, DS.Spacing.s)
        }
    }

    // MARK: - Mood + tags side by side

    private var moodAndTags: some View {
        HStack(alignment: .top, spacing: DS.Spacing.xl) {
            moodSection
                .frame(maxWidth: .infinity, alignment: .leading)
            tagsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var moodSection: some View {
        let total = store.stats.moodDistribution.reduce(0) { $0 + $1.count }
        if total > 0 {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                SectionTitle("情绪分布", subtitle: "来自 frontmatter `mood: 1-5`")
                HStack(spacing: DS.Spacing.s) {
                    ForEach(store.stats.moodDistribution) { bucket in
                        moodChip(bucket)
                    }
                }
            }
        }
    }

    private func moodChip(_ bucket: MoodBucket) -> some View {
        VStack(spacing: 4) {
            Text("\(bucket.count)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(bucket.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(moodColor(bucket.id).opacity(0.18))
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !store.stats.tagFrequency.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                SectionTitle("标签云", subtitle: "来自 frontmatter `tags:`")
                FlowLayout(spacing: 6) {
                    ForEach(store.stats.tagFrequency.prefix(40), id: \.tag) { item in
                        HStack(spacing: 4) {
                            Text(item.tag)
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(item.count)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent entries (no card, just a flowing list)

    private var recentEntries: some View {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                SectionTitle("最近 10 篇")
                VStack(spacing: 1) {
                    ForEach(store.entries.prefix(10), id: \.id) { e in
                    HStack(alignment: .top, spacing: DS.Spacing.m) {
                        Text(e.date.short)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(e.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text("\(e.wordCount) 字")
                            .font(.caption).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, DS.Spacing.m)
                    .background {
                        // Each row is its own glass strip — almost invisible, just a tint
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func moodColor(_ id: Int) -> Color {
        switch id {
        case 1: return .red
        case 2: return .orange
        case 3: return .gray
        case 4: return .green
        case 5: return .mint
        default: return .gray
        }
    }
}
