import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var updateStore: UpdateStore
    @State private var selectedTab: Tab = .stats

    /// Launch gate. Stays `false` for ~1s after first appear; during
    /// that window the launch screen is shown on top and we kick off
    /// the update check + diary reload. After the timer fires we
    /// fade the launch view out and reveal the main UI.
    @State private var isReady: Bool = false
    /// Slight delay on the fade-out (vs the immediate isReady
    /// flip) so SwiftUI has time to mount the main UI before the
    /// launch view starts animating away — otherwise the transition
    /// looks like a flash.
    @State private var launchVisible: Bool = true

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case write, stats, insight, chat, settings
        var id: String { rawValue }

        var label: String {
            switch self {
            case .write: return "写作"
            case .stats: return "统计"
            case .insight: return "洞察"
            case .chat: return "AI"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .write: return "square.and.pencil"
            case .stats: return "chart.bar.xaxis"
            case .insight: return "lightbulb"
            case .chat: return "sparkles"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        ZStack {
            // Layered liquid-glass backdrop. The animated blobs behind
            // the content give the glass surfaces something organic to refract.
            // `.allowsHitTesting(false)` so the backdrop never intercepts
            // clicks meant for the tab bar / content above it.
            LiquidBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Main UI — fades in after the launch gate clears.
            mainUI
                .opacity(isReady ? 1 : 0)
                .allowsHitTesting(isReady)

            // Launch screen on top while we're still warming up.
            if launchVisible {
                LaunchView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .tint(DS.Brand.amber)   // single brand accent for system controls
        // Default to dark mode — the amber liquid backdrop reads
        // better against a dark surface than a light one.
        .preferredColorScheme(.dark)
        .onAppear { runLaunchTasks() }
    }

    // MARK: - Launch flow

    /// Kick off the background work and schedule the launch-screen
    /// dismissal. The work itself is async — the user gets into the
    /// main UI after exactly 1s regardless of whether the network
    /// call has finished.
    private func runLaunchTasks() {
        // 1. Check for updates in the background, throttled to
        //    once per 12h. `checkAutomatically()` no-ops if the
        //    last auto-check is still inside the window. The
        //    user can always force a check from Settings — that
        //    path bypasses the throttle.
        updateStore.checkAutomatically()
        // 2. Re-scan the diary folder so the user always sees fresh
        //    entries, even if files changed on disk while the app
        //    was closed. (DiaryStore.init() already restored the last
        //    folder; reload() re-walks it.)
        store.reload()
        // 3. After exactly 1s, swap isReady on. The main UI was
        //    already mounting under the launch view during this
        //    delay, so the transition is smooth.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.35)) {
                isReady = true
            }
            // Drop the launch view 0.35s later so the main UI has
            // fully come in. Removing it earlier triggers a visible
            // flicker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                launchVisible = false
            }
        }
    }

    /// The main tab-bar + content layout, factored out so we can
    /// drive its opacity / hit-testing independently of the launch
    /// gate.
    private var mainUI: some View {
        VStack(spacing: 0) {
            // Top tab bar. No background, no overlay, no blur, no
            // gradient. Just the capsule floating on the
            // LiquidBackdrop.
            TopTabBar(
                selected: $selectedTab,
                tabs: Tab.allCases,
                label: { $0.label },
                icon: { $0.systemImage }
            )
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.m)

            // Content
            Group {
                switch selectedTab {
                case .write:    EditorTabView()
                case .stats:    StatsView()
                case .insight:  InsightView()
                case .chat:     ChatView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Custom top tab bar

/// Capsule-style tab bar that always shows. Active tab is filled with tint;
/// inactive ones are transparent. Keyboard shortcuts: Cmd+1, Cmd+2, Cmd+3.
struct TopTabBar<Tab: Identifiable & Hashable>: View {
    @Binding var selected: Tab
    let tabs: [Tab]
    let label: (Tab) -> String
    let icon: (Tab) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                tabButton(tab: tab, index: idx)
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func tabButton(tab: Tab, index: Int) -> some View {
        let isActive = (tab == selected)
        return Button {
            // No animation wrap — when the user double-clicks or rapid-tabs,
            // animations can drop the second click. Direct assignment is
            // immediate.
            selected = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(tab))
                    .font(.callout)
                Text(label(tab))
                    .font(.callout.weight(isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background {
                Group {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(DS.Brand.amber)
                            .shadow(color: DS.Brand.amber.opacity(0.45), radius: 8, y: 2)
                    }
                }
            }
            // Make the whole padded label a hit target, not just the text
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
        // Spring animation on the visual state change (active pill moves)
        // — not on the selection change, so it can't drop a click.
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

// MARK: - Animated liquid backdrop

/// A pair of slow-drifting blurred blobs behind the whole window.
/// Gives the glass surfaces something organic to refract.
struct LiquidBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // Three brand-aligned hues:
                //   p1: amber  (the afterglow itself)
                //   p2: warm rose  (complementary warm)
                //   p3: deep teal-blue  (cool counterpoint so the warm tones don't feel monotone)
                // Same colors in both modes; only the base opacity changes.
                let p1Color = DS.Brand.amber
                let p2Color = Color(red: 0.78, green: 0.45, blue: 0.55)
                let p3Color = Color(red: 0.30, green: 0.45, blue: 0.58)
                let baseOpacity: Double = colorScheme == .dark ? 0.32 : 0.50

                let p1 = blob(in: size, seed: 0, t: t, scale: 0.55)
                let p2 = blob(in: size, seed: 1, t: t, scale: 0.45)
                let p3 = blob(in: size, seed: 2, t: t, scale: 0.5)

                ctx.fill(
                    Path(ellipseIn: p1),
                    with: .radialGradient(
                        Gradient(colors: [p1Color.opacity(baseOpacity), .clear]),
                        center: CGPoint(x: p1.midX, y: p1.midY),
                        startRadius: 0,
                        endRadius: p1.width / 2
                    )
                )
                ctx.fill(
                    Path(ellipseIn: p2),
                    with: .radialGradient(
                        Gradient(colors: [p2Color.opacity(baseOpacity * 0.78), .clear]),
                        center: CGPoint(x: p2.midX, y: p2.midY),
                        startRadius: 0,
                        endRadius: p2.width / 2
                    )
                )
                ctx.fill(
                    Path(ellipseIn: p3),
                    with: .radialGradient(
                        Gradient(colors: [p3Color.opacity(baseOpacity * 0.70), .clear]),
                        center: CGPoint(x: p3.midX, y: p3.midY),
                        startRadius: 0,
                        endRadius: p3.width / 2
                    )
                )
            }
        }
    }

    private func blob(in size: CGSize, seed: Int, t: TimeInterval, scale: CGFloat) -> CGRect {
        let r = min(size.width, size.height) * scale
        let phase1 = CGFloat(t * 0.07 + Double(seed) * 1.3)
        let phase2 = CGFloat(t * 0.05 + Double(seed) * 2.1)
        let cx = size.width  * (0.3 + 0.4 * (0.5 + 0.5 * sin(phase1)))
        let cy = size.height * (0.3 + 0.4 * (0.5 + 0.5 * cos(phase2)))
        return CGRect(x: cx - r/2, y: cy - r/2, width: r, height: r)
    }
}
