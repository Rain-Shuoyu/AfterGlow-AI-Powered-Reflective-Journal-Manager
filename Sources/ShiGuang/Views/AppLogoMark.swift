import SwiftUI

/// Pure-vector recreation of the app's book+moon mark, drawn with
/// SwiftUI Path / Shape. No raster assets — every curve is a real
/// Bézier / arc so the result stays crisp at any size and on any
/// background (no checkerboard, no halo artifacts, no
/// background-plate).
///
/// Colour palette mirrors the Dock icon so the hero mark reads as
/// the same brand even though the in-app version sits on a
/// transparent canvas.
struct AppLogoMark: View {
    /// Overall square side. The mark fills it with the book on the
    /// lower half and the moon on the upper half.
    var size: CGFloat = 128

    /// Y offset for the moon layer only (the book stays put). Driven
    /// by the parent so the moon can bob independently. Negative
    /// values move the moon *up*.
    var moonOffsetY: CGFloat = 0

    // Palette — kept local to the mark.
    private let cream      = Color(red: 0.96, green: 0.91, blue: 0.79)   // page front
    private let creamEdge  = Color(red: 0.91, green: 0.83, blue: 0.66)   // page edge (slight shadow)
    private let creamBack  = Color(red: 0.86, green: 0.76, blue: 0.55)   // back cover, peeking from behind
    private let spine      = Color(red: 0.78, green: 0.62, blue: 0.40)   // centre seam / spine
    private let lineAmber  = Color(red: 0.78, green: 0.65, blue: 0.45)   // content lines on pages
    private let moonTop    = Color(red: 1.00, green: 0.93, blue: 0.66)   // moon highlight
    private let moonBottom = Color(red: 0.97, green: 0.70, blue: 0.28)   // moon shadow
    private let glow       = Color(red: 0.97, green: 0.65, blue: 0.22)   // halo

    var body: some View {
        ZStack {
            // The parent (hero) already provides the breathing outer
            // glow. Keeping this mark halo-free avoids the
            // "two concentric halos" effect where a small halo
            // inside the mark stacks on top of a larger one
            // outside. The mark itself is just book + moon; the
            // glow lives in the parent.

            // ── 1. Open book (drawn from a single Path) ────────────
            // Two trapezoid pages forming a V at the bottom, with a
            // darker back cover rectangle peeking out behind.
            ZStack {
                // Back cover — a single rounded rect, slightly wider
                // and shorter than the pages, in creamBack so the
                // pages "sit on" a visible base.
                OpenBookCover()
                    .fill(creamBack)
                    .frame(width: size * 0.74, height: size * 0.50)

                // Pages on top of the cover
                OpenBookPages()
                    .fill(
                        LinearGradient(
                            colors: [cream, creamEdge],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.74, height: size * 0.48)

                // Centre spine — a thin wedge that follows the V
                OpenBookSpine()
                    .fill(spine.opacity(0.55))
                    .frame(width: size * 0.74, height: size * 0.48)

                // Page content lines — three short rules per page,
                // in warm amber at low opacity
                pageLines
                    .frame(width: size * 0.74, height: size * 0.48)
            }
            .frame(width: size * 0.74, height: size * 0.50)
            .offset(y: size * 0.16)

            // ── 3. Crescent moon (separate layer, can bob) ─────────
            // Smooth waxing crescent drawn from two arcs. The
            // `offset(y:)` is animated by the parent for the
            // "floating moon" effect; the book stays still.
            CrescentMoonShape()
                .fill(
                    LinearGradient(
                        colors: [moonTop, moonBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    // Inner rim highlight — slightly smaller crescent
                    // stroked in the lighter moonTop, gives the moon
                    // a "lit edge" feel.
                    CrescentMoonShape()
                        .stroke(moonTop.opacity(0.7), lineWidth: 1.2)
                        .padding(2)
                }
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(y: -size * 0.05 + moonOffsetY)
                .shadow(color: glow.opacity(0.45), radius: 6, x: 0, y: 0)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Page lines

    /// Three short horizontal lines on each page, drawn in amber at
    /// low opacity. Sits inside the page rect; the ZStack in `body`
    /// places it on top of the pages.
    private var pageLines: some View {
        HStack(spacing: size * 0.04) {
            ForEach(0..<2) { _ in
                VStack(alignment: .leading, spacing: size * 0.022) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                            .fill(lineAmber.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: 1.5)
                    }
                }
                .padding(.horizontal, size * 0.04)
                .padding(.vertical, size * 0.045)
            }
        }
    }
}

// MARK: - Open book shapes
//
// All three book parts (cover, pages, spine) are drawn from custom
// Path / Shape so they share a single coordinate system and align
// pixel-perfect. The `rect` passed in is the page's bounding box;
// each shape knows how to draw its own trapezoid within that box.

/// Back cover — a single rounded rectangle. Slightly wider than
/// the pages so a thin sliver peeks out at the bottom.
struct OpenBookCover: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 3, style: .continuous)
    }
}

/// Pages — two trapezoids meeting at a V at the bottom-centre.
/// Trapezoid edges: top edge is shorter than bottom edge (foreshortening
/// because the open book is "tilted forward"); the inner edges meet
/// at a point at (midX, maxY - vDepth).
struct OpenBookPages: Shape {
    /// How deep the V at the bottom-centre is, as a fraction of height.
    var vDepth: CGFloat = 0.18

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let topInset = w * 0.04
        let v = h * vDepth

        // Left page: TL → spine-top → spine-bottom (V) → BL → close
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: cx,           y: rect.minY + h * 0.04))
        p.addLine(to: CGPoint(x: cx,           y: rect.maxY - v))
        p.addLine(to: CGPoint(x: rect.minX,     y: rect.maxY))
        p.closeSubpath()

        // Right page: spine-top → TR → BR → spine-bottom (V) → close
        p.move(to: CGPoint(x: cx,           y: rect.minY + h * 0.04))
        p.addLine(to: CGPoint(x: rect.maxX,    y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX,    y: rect.maxY))
        p.addLine(to: CGPoint(x: cx,           y: rect.maxY - v))
        p.closeSubpath()

        // Suppress unused warning
        _ = topInset
        return p
    }
}

/// Centre spine — a thin wedge that follows the V on top of the
/// pages. Two triangles meeting at (midX, maxY - v).
struct OpenBookSpine: Shape {
    var vDepth: CGFloat = 0.18

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let v = rect.height * vDepth
        let halfWidth: CGFloat = 1.5

        p.move(to: CGPoint(x: cx - halfWidth, y: rect.minY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: cx + halfWidth, y: rect.minY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: cx,              y: rect.maxY - v))
        p.closeSubpath()
        return p
    }
}

// MARK: - Crescent moon
//
// A proper crescent drawn from two arcs in a single Path. The outer
// arc traces a full circle; the inner arc (offset to the right)
// traces a counter-rotation that the default non-zero fill rule
// treats as a "subtraction", leaving just the crescent body.
//
// The shape is parameterised so callers can tweak the crescent's
// "thinness" (inner radius) and "tilt" (offset ratio) without
// having to hand-edit the path.

struct CrescentMoonShape: Shape {
    /// How far the inner cutout shifts right, as a fraction of width.
    /// 0 = full circle, 0.5 = thin crescent, 0.7 = very thin sliver.
    var innerOffsetRatio: CGFloat = 0.30
    /// How big the inner cutout is, as a fraction of the outer radius.
    /// <1 = crescent, 1 = half-moon, >1 = gibbous (reversed).
    var innerRadiusRatio: CGFloat = 0.80
    /// Extra vertical stretch on the inner cutout, makes the crescent
    /// "reach" a little past the top/bottom of the outer disc.
    var innerHeightBoost: CGFloat = 0.06

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let outerR = min(rect.width, rect.height) / 2
        let outerCenter = CGPoint(x: rect.midX, y: rect.midY)
        let innerR = outerR * innerRadiusRatio
        let innerOffset = outerR * innerOffsetRatio
        let innerCenter = CGPoint(
            x: outerCenter.x + innerOffset,
            y: outerCenter.y
        )
        // Trace the outer circle clockwise, then the inner circle
        // also clockwise (same winding) so the non-zero fill rule
        // subtracts it — leaving just the crescent. We extend the
        // inner arc slightly past the top/bottom so the tips of
        // the crescent come to clean points instead of being
        // truncated by the outer circle.
        let innerRExtended = innerR
        let innerTopY = outerCenter.y - innerRExtended - rect.height * innerHeightBoost
        let innerBotY = outerCenter.y + innerRExtended + rect.height * innerHeightBoost

        p.addArc(
            center: outerCenter,
            radius: outerR,
            startAngle: .degrees(-90),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.addArc(
            center: innerCenter,
            radius: innerRExtended,
            startAngle: .degrees(atan2(innerBotY - innerCenter.y, 0)),
            endAngle: .degrees(atan2(innerTopY - innerCenter.y, 0)),
            clockwise: true
        )
        p.closeSubpath()
        return p
    }
}
