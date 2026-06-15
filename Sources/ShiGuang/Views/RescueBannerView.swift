import SwiftUI

/// Top-of-screen banner for the "🌧 情绪急救" intervention.
///
/// Cool blue (vs the warm amber of other banners) signals
/// "this is different from your usual badges — read it
/// carefully, but you can also dismiss it".
struct RescueBannerView: View {
    let level: RescueSignal.Level
    let onTap: () -> Void
    let onDismissToday: () -> Void

    private var accent: Color {
        switch level {
        case .intervene:
            return Color(red: 0.55, green: 0.70, blue: 0.85)
        case .watch:
            return Color(red: 0.65, green: 0.75, blue: 0.85)
        case .none:
            return DS.Brand.amber
        }
    }

    private var title: String {
        switch level {
        case .intervene: return "你之前走过这段路"
        case .watch:     return "你最近几天都不太好"
        case .none:      return ""
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(level == .intervene ? "🌧" : "☁️")
                .font(.system(size: 16))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onTap) {
                Text("看看")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(accent)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button(action: onDismissToday) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
            .help("今日不再显示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.35), lineWidth: 0.5)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
