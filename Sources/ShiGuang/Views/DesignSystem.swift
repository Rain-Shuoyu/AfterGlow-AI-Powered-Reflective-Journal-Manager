import SwiftUI

// MARK: - Design tokens

/// Centralised style tokens for the liquid-glass look.
/// Everything visual that needs to stay consistent across views lives here.
enum DS {
    /// Squircle corner radii (continuous / iOS-style, not circular).
    enum Radius {
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Opacity {
        static let glassSubtle: Double = 0.55
        static let glassRegular: Double = 0.7
        static let glassProminent: Double = 0.85
    }

    /// 拾光 (Afterglow) brand palette. Single accent color used everywhere
    /// "chrome" so the app reads as one voice. Data-semantic colors (mood
    /// 1–5, etc.) are deliberately *not* in here — they stay neutral and
    /// always mean the same thing.
    enum Brand {
        /// Primary amber — the afterglow. Used for active tabs, primary
        /// buttons, user message bubbles, etc.
        static let amber = Color(red: 0.91, green: 0.66, blue: 0.49)        // #E8A87C

        /// Slightly more saturated amber — hover/active states, halo glows.
        static let amberDeep = Color(red: 0.95, green: 0.64, blue: 0.38)    // #F4A261

        /// Tinted backgrounds (chip fills, hover states). Use opacity 0.10–0.20.
        static let amberSoft = Color(red: 0.91, green: 0.66, blue: 0.49).opacity(0.14)

        /// Deep ink — window base. Slight warm cast, not pure black.
        static let ink = Color(red: 0.06, green: 0.07, blue: 0.09)         // #0F1116

        /// Slightly raised surface (cards, modals).
        static let inkRaised = Color(red: 0.10, green: 0.11, blue: 0.14)   // #1A1D24

        /// Warm paper — primary text in dark mode.
        static let paper = Color(red: 0.96, green: 0.94, blue: 0.91)      // #F5F0E8

        /// Warm secondary text.
        static let warmGray = Color(red: 0.64, green: 0.62, blue: 0.57)   // #A39E92
    }

    /// Data-semantic colors. Only used where the *meaning* of the color matters
    /// (mood 1–5, error/success, etc.). Do NOT use these for decoration.
    enum Mood {
        static func color(_ mood: Int?) -> Color {
            switch mood {
            case 1: return Color(red: 0.93, green: 0.42, blue: 0.42)         // muted red
            case 2: return Color(red: 0.95, green: 0.62, blue: 0.36)         // muted orange
            case 3: return Color(red: 0.60, green: 0.60, blue: 0.58)         // warm gray
            case 4: return Color(red: 0.52, green: 0.78, blue: 0.58)         // muted green
            case 5: return Color(red: 0.46, green: 0.86, blue: 0.72)         // muted mint
            default: return Brand.amber
            }
        }
    }
}

extension View {
    /// Squircle / continuous rounded-rectangle shape (matches system app icons).
    func squircle(_ radius: CGFloat) -> some View {
        clipShape(.rect(cornerRadius: radius, style: .continuous))
    }

    /// Apply a liquid-glass material to the view's background. Use sparingly —
    /// typically on a single root container, not on every row.
    func liquidGlass(_ material: Glass = .regular, tint: Color? = nil) -> some View {
        self.background {
            if let tint {
                tint.opacity(0.12)
            }
        }
        .glassEffect(material, in: .rect(cornerRadius: DS.Radius.l, style: .continuous))
    }

    /// Drop the old "card with hard background" look: turn off the section-card
    /// styling so the view sits on the parent glass surface directly.
    func deCard() -> some View { self }
}

// MARK: - Custom container shapes

/// Soft "blob" background used behind the heatmap and chart — gives the
/// data viz a subtle enclosure without feeling like a card.
struct LiquidPanel: ViewModifier {
    var radius: CGFloat = DS.Radius.xl
    func body(content: Content) -> some View {
        content
            .padding(DS.Spacing.l)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.background.opacity(0.001))   // hit-test area only
            }
    }
}

extension View {
    /// Wrap a view in a "panel" — no card background, but a generous rounded
    /// padding region with consistent corner radius. Use to demarcate sections
    /// inside a glass root, without stacking opaque cards.
    func liquidPanel(radius: CGFloat = DS.Radius.xl) -> some View {
        modifier(LiquidPanel(radius: radius))
    }
}

// MARK: - Reusable controls

/// Pill-shaped primary button with liquid-glass background and spring press.
struct LiquidButton: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void
    @State private var pressed = false

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s) }
                Text(title)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            }
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .onHover { pressed = $0 }
    }
}

/// Compact key-value row used in the stat strip and settings.
struct StatPill: View {
    let label: String
    let value: String
    let systemImage: String
    /// Optional override (e.g. mood 1 → muted red). When `nil`, brand amber.
    var tint: Color? = nil

    private var iconColor: Color { tint ?? DS.Brand.amber }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s + 2)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Section heading — large title style with optional subtitle, no card.
struct SectionTitle: View {
    let title: String
    let subtitle: String?
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let s = subtitle {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Date helper

extension Date {
    var short: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: self)
    }
}

// MARK: - Markdown text

/// Renders a markdown string. Code blocks (```) are extracted and rendered as
/// monospaced text on a tinted background; the rest is parsed as inline markdown
/// via `AttributedString` (handles **bold**, *italic*, `code`, [links](url)).
struct MarkdownText: View {
    let markdown: String
    var baseFont: Font = .body

    var body: some View {
        let segments = Self.split(markdown)
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                if seg.isCode {
                    codeBlock(seg.text)
                } else {
                    inlineMarkdown(seg.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineMarkdown(_ s: String) -> some View {
        // Use .full so headings (#, ##, ###) and lists (-, 1.) are also
        // rendered, not just inline elements like **bold** and *italic*.
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full
        )
        if let attr = try? AttributedString(markdown: s, options: opts) {
            Text(attr)
                .font(baseFont)
                .textSelection(.enabled)
        } else {
            Text(s)
                .font(baseFont)
                .textSelection(.enabled)
        }
    }

    private func codeBlock(_ s: String) -> some View {
        Text(s)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(DS.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(.tint.opacity(0.10))
            }
    }

    // MARK: - Code-block splitter

    fileprivate struct Segment { let text: String; let isCode: Bool }

    fileprivate static func split(_ s: String) -> [Segment] {
        var result: [Segment] = []
        var inCode = false
        var buf: [String] = []
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if !buf.isEmpty {
                    result.append(.init(text: buf.joined(separator: "\n"), isCode: inCode))
                    buf.removeAll()
                }
                inCode.toggle()
                continue
            }
            buf.append(line)
        }
        if !buf.isEmpty {
            result.append(.init(text: buf.joined(separator: "\n"), isCode: inCode))
        }
        if result.isEmpty {
            result.append(.init(text: s, isCode: false))
        }
        return result
    }
}

// MARK: - Flow layout (for tag chips / question chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
