import SwiftUI

/// Full-screen launch gate shown for ~1s on app startup. While
/// visible, the parent `ContentView` kicks off background work
/// (update check, diary reload). After the timer fires the view
/// fades out and the main UI fades in.
struct LaunchView: View {
    @State private var phase: CGFloat = 0
    @State private var dot: Int = 0   // 0/1/2 — three-dot pulse

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Same dark canvas as the main app, so the transition
            // is seamless. The `LiquidBackdrop` is rendered behind
            // the main UI — duplicating it here would just add
            // a second pass for no visible reason.
            Color(red: 0.07, green: 0.07, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: DS.Spacing.l) {
                Spacer()
                AppLogoMark(size: 160, moonOffsetY: 0)
                    .frame(width: 160, height: 160)
                VStack(spacing: 8) {
                    Text("拾光")
                        .font(.system(size: 36, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                    Text("用 AI 重新看见你的日记")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                progressDots
                    .padding(.bottom, DS.Spacing.xl)
            }
        }
        // Subtle entry: scale from 0.92 + fade in. The whole view
        // exits with an opacity tween (driven by the parent).
        .scaleEffect(0.96 + 0.04 * phase)
        .opacity(0.4 + 0.6 * phase)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { phase = 1 }
        }
        .onReceive(timer) { _ in
            // Three-dot pulse — cheap, no extra state, no extra
            // view hierarchy. Each tick advances `dot`; the dots'
            // opacity is bound to it so they cascade.
            dot = (dot + 1) % 3
        }
    }

    /// Three horizontally-arranged dots; one is brighter at a time
    /// to suggest "loading" without being noisy.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DS.Brand.amber)
                    .frame(width: 6, height: 6)
                    .opacity(i == dot ? 1.0 : 0.25)
                    .animation(.easeInOut(duration: 0.3), value: dot)
            }
        }
    }
}
