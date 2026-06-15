import SwiftUI

/// The "Insight" tab container. Switches between a linear timeline view and
/// an Obsidian-style entity graph view via a top-left segmented control.
struct InsightView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var practiceStore: DailyPracticeStore
    @EnvironmentObject var anniversaryStore: AnniversaryStore
    @EnvironmentObject var rescueStore: RescueStore

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
    /// When true, the "🌙 今日签" sheet is shown.
    @State private var showDailyPractice: Bool = false
    /// When true, the "🕯 周年回响" sheet is shown.
    @State private var showAnniversary: Bool = false
    /// When true, the "🪞 镜像" sheet is shown.
    @State private var showMirror: Bool = false
    /// When true, the "🌧 情绪急救" sheet is shown.
    @State private var showRescue: Bool = false

    /// Cached list of anniversary entries for today. Recomputed
    /// when `store.entries` changes (via .onChange).
    @State private var anniversaryEntries: [AnniversaryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top-left view switcher + 回溯 + 今日签 + 周年
            HStack(alignment: .center, spacing: DS.Spacing.m) {
                ModePicker(mode: $mode)
                Spacer()
                dailyPracticeButton
                flashbackButton
                mirrorButton
                anniversaryButton
                rescueButton
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)

            // Optional anniversary banner
            if anniversaryStore.shouldShowBanner(today: Date(), entries: store.entries) {
                AnniversaryBannerView(
                    onTap: {
                        anniversaryStore.markShown()
                        showAnniversary = true
                    },
                    onDismissToday: {
                        anniversaryStore.dismissForToday()
                    },
                    yearsAgo: anniversaryEntries.map { $0.yearsAgo }
                )
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Optional rescue banner
            if rescueStore.shouldShowBanner(entries: store.entries) {
                RescueBannerView(
                    level: rescueStore.currentSignal(entries: store.entries).level,
                    onTap: {
                        rescueStore.markShown()
                        showRescue = true
                    },
                    onDismissToday: {
                        rescueStore.dismissForToday()
                    }
                )
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
        .sheet(isPresented: $showDailyPractice) {
            DailyPracticeSheet()
                .environmentObject(practiceStore)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAnniversary) {
            AnniversarySheet(entries: anniversaryEntries)
                .environmentObject(store)
        }
        .sheet(isPresented: $showMirror) {
            MirrorSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showRescue) {
            RescueSheet(signal: rescueStore.currentSignal(entries: store.entries))
                .environmentObject(store)
                .environmentObject(rescueStore)
        }
        .onAppear {
            recomputeAnniversaries()
        }
        .onChange(of: store.entries) { _, _ in
            recomputeAnniversaries()
        }
        // The sub-views own their own headers; make sure no top inset lingers.
        .navigationTitle("")
        .toolbar(.hidden)
    }

    private func recomputeAnniversaries() {
        anniversaryEntries = AnniversaryFinder.find(in: store.entries)
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

    /// "🌙 今日签" button — opens the daily micro-practice sheet.
    /// Always enabled (no LLM call). When the user has already
    /// completed today, the badge shows a checkmark; otherwise
    /// it shows a moon.
    private var dailyPracticeButton: some View {
        Button {
            showDailyPractice = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: practiceStore.isTodayDone
                      ? "checkmark.seal.fill"
                      : "moon.stars.fill")
                Text("今日签")
                if let badge = streakBadgeText {
                    streakBadge(badge)
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Brand.amber.opacity(practiceStore.isTodayDone ? 0.28 : 0.16))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.5), lineWidth: 0.8)
            }
            .foregroundStyle(DS.Brand.amberDeep)
        }
        .buttonStyle(.plain)
        .help(practiceStore.isTodayDone
              ? "今天的内省已经完成 · \(streakHelpText)"
              : "今天的小内省：1-2 分钟 · \(streakHelpText)")
    }

    /// Streak text shown next to the "今日签" label. Only
    /// appears for streaks ≥ 3 days (gentle — no pressure for
    /// first-timers). Format:
    ///   - "🔥 7" when today is done and streak ≥ 3
    ///   - "7" when today not done but streak alive
    ///   - nil otherwise
    private var streakBadgeText: String? {
        let s = practiceStore.streak
        guard s >= 3 else { return nil }
        if practiceStore.isTodayDone {
            return "🔥 \(s)"
        }
        return "\(s)"
    }

    private var streakHelpText: String {
        let s = practiceStore.streak
        let longest = practiceStore.longestStreak
        if s == 0 {
            return "从今天开始你的 streak"
        }
        if s >= longest {
            return "连续 \(s) 天 · 新纪录"
        }
        return "连续 \(s) 天 · 最长 \(longest) 天"
    }

    /// Tiny pill badge for the streak number. Slightly more
    /// saturated than the button itself so it pops.
    private func streakBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(DS.Brand.amberDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule().fill(DS.Brand.amber.opacity(0.45))
            )
    }

    /// "🕯 周年" button — opens the anniversary sheet
    /// manually, even outside the ±1 day window. Disabled when
    /// there are no matching entries.
    private var anniversaryButton: some View {
        Button {
            showAnniversary = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                Text("周年")
                if !anniversaryEntries.isEmpty {
                    Text("\(anniversaryEntries.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Brand.amberDeep)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(DS.Brand.amber.opacity(0.45))
                        )
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Brand.amber.opacity(0.16))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.5), lineWidth: 0.8)
            }
            .foregroundStyle(DS.Brand.amberDeep)
        }
        .buttonStyle(.plain)
        .disabled(anniversaryEntries.isEmpty)
        .opacity(anniversaryEntries.isEmpty ? 0.5 : 1)
        .help(anniversaryEntries.isEmpty
              ? "往年的今天还没有日记"
              : "往年的今天你写过 \(anniversaryEntries.count) 篇")
    }

    /// "🪞 镜像" button — opens the mirror reflection sheet.
    /// Disabled when there are fewer than 5 entries (the sampler
    /// needs at least that many to produce a meaningful set).
    private var mirrorButton: some View {
        Button {
            showMirror = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "circle.dashed")
                Text("镜像")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(DS.Brand.amber.opacity(0.16))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.5), lineWidth: 0.8)
            }
            .foregroundStyle(DS.Brand.amberDeep)
        }
        .buttonStyle(.plain)
        .disabled(store.entries.count < 5)
        .opacity(store.entries.count < 5 ? 0.5 : 1)
        .help(store.entries.count < 5
              ? "至少写 5 篇之后才能回看"
              : "从你过去的日记里挑 5-7 句")
    }

    /// "🌧 急救" button — manual rescue entry-point. Disabled
    /// when the rescue signal isn't currently active, so the
    /// user can't accidentally surface "you're not in distress"
    /// content as if it were one. The signal + banner logic is
    /// in `RescueStore.shouldShowBanner`.
    private var rescueButton: some View {
        Button {
            showRescue = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud.rain.fill")
                Text("急救")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(red: 0.45, green: 0.55, blue: 0.65).opacity(0.18))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color(red: 0.55, green: 0.70, blue: 0.85).opacity(0.5), lineWidth: 0.8)
            }
            .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 0.85))
        }
        .buttonStyle(.plain)
        .disabled(rescueStore.currentSignal(entries: store.entries).level == .none)
        .opacity(rescueStore.currentSignal(entries: store.entries).level == .none ? 0.5 : 1)
        .help("查看你之前是怎么走出低谷的")
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
