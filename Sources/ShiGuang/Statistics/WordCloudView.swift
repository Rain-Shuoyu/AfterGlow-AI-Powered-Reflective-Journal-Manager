import SwiftUI

/// Word-cloud style frequency view. Each word's font size scales with its
/// frequency; all words use the brand amber (single-color treatment so it
/// reads as one voice, not a rainbow of tag colors).
struct WordCloudView: View {
    let words: [(word: String, count: Int)]

    var body: some View {
        if words.isEmpty {
            Text("暂无内容")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, item in
                    Text(item.word)
                        .font(.system(size: fontSize(for: item.count),
                                      weight: .medium,
                                      design: .rounded))
                        .foregroundStyle(DS.Brand.amber.opacity(opacity(for: item.count)))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Linear interpolation between the smallest and largest counts in this
    /// set. Top word = maxSize, lowest word = minSize.
    private func fontSize(for count: Int) -> CGFloat {
        guard let maxCount = words.map(\.count).max(), let minCount = words.map(\.count).min() else {
            return 13
        }
        let range = CGFloat(max(maxCount - minCount, 1))
        let t = CGFloat(count - minCount) / range
        return 11 + t * 16  // 11pt … 27pt
    }

    private func opacity(for count: Int) -> Double {
        guard let maxCount = words.map(\.count).max(), let minCount = words.map(\.count).min() else {
            return 0.7
        }
        let range = Double(max(maxCount - minCount, 1))
        let t = Double(count - minCount) / range
        return 0.55 + t * 0.45   // 0.55 … 1.0
    }
}
