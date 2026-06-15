import SwiftUI

/// Compact banner that appears at the top of the Insight tab on
/// days inside the anniversary window. Tap → open the sheet.
/// "✕" → dismiss for today (reappears next anniversary window
///            unless toggled off permanently in settings).
struct AnniversaryBannerView: View {
    let onTap: () -> Void
    let onDismissToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("🕯")
                .font(.system(size: 16))
            Text("往年的今天，你写过")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onTap) {
                Text("回看")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(DS.Brand.amber)
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
                .fill(DS.Brand.amber.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Brand.amber.opacity(0.30), lineWidth: 0.5)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
