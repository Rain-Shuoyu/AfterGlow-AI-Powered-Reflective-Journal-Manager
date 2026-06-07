import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedTab: Tab = .stats

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case stats, insight, chat, settings
        var id: String { rawValue }

        var label: String {
            switch self {
            case .stats: return "统计"
            case .insight: return "洞察"
            case .chat: return "AI"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
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
            LiquidBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Always-visible custom top tab bar (replaces macOS 26's
                // default TabView which auto-hides tabs on certain states).
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
                    case .stats:    StatsView()
                    case .insight:  InsightView()
                    case .chat:     ChatView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .tint(.accentColor)
        // Default to dark mode — the colorful liquid backdrop reads
        // better against a dark surface than a light one.
        .preferredColorScheme(.dark)
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selected = tab
            }
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
                            .fill(.tint)
                            .shadow(color: .accentColor.opacity(0.4), radius: 8, y: 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
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
                let p1Color: Color = colorScheme == .dark
                    ? Color(red: 0.30, green: 0.50, blue: 0.95)
                    : Color(red: 0.45, green: 0.70, blue: 1.0)
                let p2Color: Color = colorScheme == .dark
                    ? Color(red: 0.85, green: 0.35, blue: 0.65)
                    : Color(red: 0.95, green: 0.55, blue: 0.85)
                let p3Color: Color = colorScheme == .dark
                    ? Color(red: 0.30, green: 0.75, blue: 0.55)
                    : Color(red: 0.55, green: 0.90, blue: 0.75)
                let baseOpacity: Double = colorScheme == .dark ? 0.35 : 0.55

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
                        Gradient(colors: [p2Color.opacity(baseOpacity * 0.85), .clear]),
                        center: CGPoint(x: p2.midX, y: p2.midY),
                        startRadius: 0,
                        endRadius: p2.width / 2
                    )
                )
                ctx.fill(
                    Path(ellipseIn: p3),
                    with: .radialGradient(
                        Gradient(colors: [p3Color.opacity(baseOpacity * 0.75), .clear]),
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
