import SwiftUI

/// Compact banner that appears at the top of the Insight tab on
/// days inside the anniversary window. Tap → open the sheet.
/// "✕" → dismiss for today (reappears next anniversary window
///         unless toggled off permanently in settings).
///
/// The banner carries a small year-spans badge (e.g. "1/2/3
/// 年前") so the user knows how far back the matches go without
/// having to open the sheet.
struct AnniversaryBannerView: View {
    let onTap: () -> Void
    let onDismissToday: () -> Void
    /// Years-ago values for the matching entries, e.g. [1, 2, 3].
    /// Used to render a small badge like "1/2/3 年前".
    let yearsAgo: [Int]

    init(onTap: @escaping () -> Void, onDismissToday: @escaping () -> Void, yearsAgo: [Int]) {
        self.onTap = onTap
        self.onDismissToday = onDismissToday
        self.yearsAgo = yearsAgo
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("🕯")
                .font(.system(size: 16))
            Text("往年的今天，你写过")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            if !yearsAgo.isEmpty {
                Text(yearBadgeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Brand.amberDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(DS.Brand.amber.opacity(0.30))
                    )
            }
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

    /// Compact years-ago label. Examples:
    ///   - [1]       → "1 年前"
    ///   - [1, 2]    → "1/2 年前"
    ///   - [1, 2, 3] → "1/2/3 年前"
    private var yearBadgeText: String {
        let sorted = yearsAgo.sorted()
        return sorted.map { "\($0)" }.joined(separator: "/") + " 年前"
    }
}
