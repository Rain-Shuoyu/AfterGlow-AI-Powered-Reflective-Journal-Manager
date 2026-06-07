import SwiftUI

/// Word-cloud style frequency view. Two-zone layout:
///   1. "Featured" zone — top 4 most-frequent words in larger type, aligned in a
///      horizontal row with extra spacing. Anchors the view.
///   2. "Cloud" zone — the rest, smaller, packed via FlowLayout.
///
/// Every word uses the brand amber (single-color treatment so it reads as one
/// voice, not a rainbow).
struct WordCloudView: View {
    let words: [(word: String, count: Int)]

    /// How many words get the "featured" treatment at the top.
    private let featuredCount = 4

    private var featured: [(word: String, count: Int)] {
        Array(words.prefix(featuredCount))
    }
    private var cloud: [(word: String, count: Int)] {
        Array(words.dropFirst(featuredCount))
    }

    var body: some View {
        if words.isEmpty {
            Text("暂无内容")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                featuredZone
                cloudZone
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Featured (top zone)

    private var featuredZone: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(featured.enumerated()), id: \.offset) { idx, item in
                featuredWord(item, rank: idx)
            }
        }
    }

    private func featuredWord(_ item: (word: String, count: Int), rank: Int) -> some View {
        // Featured: 18..26pt, full opacity, a touch more letter-spacing.
        let size: CGFloat = 26 - CGFloat(rank) * 2.5
        return Text(item.word)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.Brand.amber)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    // MARK: - Cloud (bottom zone)

    private var cloudZone: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(cloud.enumerated()), id: \.offset) { _, item in
                Text(item.word)
                    .font(.system(size: cloudSize(for: item.count),
                                  weight: .regular,
                                  design: .rounded))
                    .foregroundStyle(DS.Brand.amber.opacity(cloudOpacity(for: item.count)))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
            }
        }
    }

    private func cloudSize(for count: Int) -> CGFloat {
        guard let maxCount = words.map(\.count).max(),
              let minCount = words.map(\.count).min() else { return 11 }
        let range = CGFloat(max(maxCount - minCount, 1))
        let t = CGFloat(count - minCount) / range
        return 10 + t * 9   // 10pt … 19pt
    }

    private func cloudOpacity(for count: Int) -> Double {
        guard let maxCount = words.map(\.count).max(),
              let minCount = words.map(\.count).min() else { return 0.7 }
        let range = Double(max(maxCount - minCount, 1))
        let t = Double(count - minCount) / range
        return 0.55 + t * 0.40
    }
}
