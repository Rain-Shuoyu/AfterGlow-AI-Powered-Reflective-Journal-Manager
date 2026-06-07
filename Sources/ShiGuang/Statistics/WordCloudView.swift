import SwiftUI
import AppKit

/// Wordle-style word cloud. Words are placed greedily in a spiral starting
/// from the center: largest first, each subsequent word tries positions on
/// an Archimedean spiral until it finds a non-overlapping slot that fits
/// inside the canvas. All words are horizontal, single brand-amber color,
/// font size 11–26pt and opacity 0.6–1.0 scaled to count.
struct WordCloudView: View {
    let words: [(word: String, count: Int)]

    /// Max words to attempt to place. Beyond this the cloud gets too dense.
    private let maxWords = 40
    /// Outer canvas size. Auto-set by the parent so it can adapt to layout.
    private let canvasSize = CGSize(width: 300, height: 240)

    var body: some View {
        if words.isEmpty {
            Text("暂无内容")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            Canvas { ctx, size in
                let placed = computeLayout(in: size)
                for p in placed {
                    let txt = Text(p.word)
                        .font(.system(size: p.fontSize, weight: p.weight, design: .rounded))
                        .foregroundStyle(DS.Brand.amber.opacity(p.opacity))
                    ctx.draw(txt, at: CGPoint(x: p.frame.midX, y: p.frame.midY))
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }

    // MARK: - Layout

    private struct Placed {
        let word: String
        let fontSize: CGFloat
        let weight: Font.Weight
        let opacity: Double
        let frame: CGRect
    }

    /// Greedy spiral placement. Returns words that fit in the canvas.
    private func computeLayout(in size: CGSize) -> [Placed] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let sorted = words.sorted { $0.count > $1.count }
        let maxCount = sorted.first?.count ?? 1
        let minCount = sorted.last?.count ?? 1
        let range = CGFloat(max(maxCount - minCount, 1))

        var placed: [Placed] = []
        let limited = sorted.prefix(maxWords)

        for item in limited {
            // Map count → font size (11 … 26pt) and opacity (0.6 … 1.0).
            // Top words (highest count) get the larger size + bold.
            let t = range > 0 ? CGFloat(item.count - minCount) / range : 0
            let fontSize: CGFloat = 11 + t * 15
            let weight: Font.Weight = t > 0.65 ? .semibold : .regular
            let opacity: Double = 0.6 + Double(t) * 0.4

            // Measure the actual text so packing is honest.
            let attr = NSAttributedString(string: item.word, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(weight))
            ])
            let textSize = attr.size()
            let textRect = CGRect(origin: .zero, size: textSize)

            // Try positions on a spiral from the center outward.
            var foundFrame: CGRect? = nil
            let step: CGFloat = 1.4
            let maxRadius = hypot(size.width, size.height)
            var theta: CGFloat = 0
            while theta < 80 {  // enough revolutions to fill any canvas
                let r = step * theta
                let cx = center.x + r * cos(theta)
                let cy = center.y + r * sin(theta)
                let candidate = CGRect(
                    x: cx - textSize.width / 2,
                    y: cy - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                // Must fit inside the canvas
                let inBounds = candidate.minX >= 0 &&
                               candidate.minY >= 0 &&
                               candidate.maxX <= size.width &&
                               candidate.maxY <= size.height

                if inBounds && !placed.contains(where: { $0.frame.intersects(candidate.insetBy(dx: 2, dy: 1)) }) {
                    foundFrame = candidate
                    break
                }

                theta += 0.18
                if step * theta > maxRadius { break }
            }

            if let frame = foundFrame {
                placed.append(Placed(
                    word: item.word,
                    fontSize: fontSize,
                    weight: weight,
                    opacity: opacity,
                    frame: frame
                ))
            }
            // If no frame found, this word doesn't fit — skip it. (Don't add
            // it because drawing it on top of nothing would look broken.)
            _ = textRect  // silence unused-warning in case we drop the rect
        }

        return placed
    }
}

// NSFont.Weight doesn't bridge to Font.Weight directly; provide a tiny helper.
private extension NSFont.Weight {
    init(_ fw: Font.Weight) {
        switch fw {
        case .bold:        self = .bold
        case .semibold:    self = .semibold
        case .regular:     self = .regular
        case .light:       self = .light
        default:            self = .regular
        }
    }
}
