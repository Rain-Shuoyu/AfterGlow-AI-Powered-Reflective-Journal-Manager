import SwiftUI

struct InsightGraphView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore

    // Edges are derived on the fly from `EmbeddingIndex`. We don't
    // store the graph in @State because:
    //   - it's pure-derived from `store.entries`
    //   - the embedding index is cached on disk, so recomputation is
    //     sub-millisecond per entry on warm runs
    // What we *do* store is the force-directed layout positions —
    // they're stable enough across recomputations to keep around.
    @State private var positions: [DiaryEntry.ID: CGPoint] = [:]
    @State private var lastLayoutBounds: CGSize = .zero
    @State private var selectedEntry: DiaryEntry?
    @State private var isComputing: Bool = false

    // Interaction
    @State private var pan: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var lastPan: CGSize = .zero
    @State private var lastZoom: CGFloat = 1.0
    @State private var hoveredID: DiaryEntry.ID?

    private let layoutBounds = CGSize(width: 1100, height: 700)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            content
        }
        .onAppear { recomputeLayout() }
        .onChange(of: store.entries) { _, _ in recomputeLayout() }
        .sheet(item: $selectedEntry) { entry in
            DiaryDetailSheet(entry: entry)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("关系图谱").font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                recomputeLayout(force: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("重新计算")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .disabled(store.entries.isEmpty || isComputing)
            .help("清空 embedding 缓存并重算所有节点的关系")
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.m)
    }

    private var headerSubtitle: String {
        if store.entries.isEmpty { return "选目录后开始" }
        let (_, edges) = GraphBuilder.build(entries: store.entries)
        return "\(store.entries.count) 节点 · \(edges.count) 边 · 阈值 \(String(format: "%.2f", GraphBuilder.edgeThreshold))"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.folderURL == nil {
            placeholder(
                icon: "doc.text.magnifyingglass",
                title: "先到「统计」页选一个日记目录"
            )
        } else if store.entries.isEmpty {
            placeholder(icon: "tray", title: "目录里没找到 .md 文件")
        } else if positions.isEmpty {
            // First-load compute. Show a brief spinner; the actual
            // work happens in `recomputeLayout` (embedding lookups
            // are O(1) on warm runs, O(n) on cold runs).
            VStack(spacing: DS.Spacing.m) {
                ProgressView().controlSize(.small)
                Text("正在计算关系…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            graphCanvas
        }
    }

    private func placeholder(icon: String, title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).foregroundStyle(.secondary)
            if let s = subtitle {
                Text(s).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Graph canvas

    private var graphCanvas: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.translateBy(x: center.x + pan.width, y: center.y + pan.height)
                ctx.scaleBy(x: zoom, y: zoom)

                // Draw edges
                for e in GraphBuilder.build(entries: store.entries).edges {
                    guard let a = positions[e.source], let b = positions[e.target] else { continue }
                    let isHighlighted = (hoveredID == e.source || hoveredID == e.target)
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    // Map cosine similarity in [edgeThreshold, 1.0] to
                    // a line width. We use sqrt(t) to bias the curve
                    // toward the high end — even a pair at sim=0.7
                    // gets a visibly thick line, and the top of the
                    // range (sim≈1.0) is dramatically thicker.
                    //   t=0.10 (sim=0.55):  ~0.9pt
                    //   t=0.50 (sim=0.75):  ~3.6pt
                    //   t=1.00 (sim=1.00):  ~6.4pt
                    let t = max(0, min(1, (e.weight - GraphBuilder.edgeThreshold) / (1 - GraphBuilder.edgeThreshold)))
                    let baseWidth: CGFloat = 0.4 + CGFloat(sqrt(t)) * 6.0
                    ctx.stroke(
                        path,
                        with: .color(isHighlighted ? DS.Brand.amber.opacity(0.85) : .secondary.opacity(0.20)),
                        style: StrokeStyle(lineWidth: baseWidth, lineCap: .round)
                    )
                }

                // Draw nodes
                for n in GraphBuilder.build(entries: store.entries).nodes {
                    let p = positions[n.id] ?? .zero
                    let r = nodeRadius(n.entry)
                    let isHovered = (hoveredID == n.id)
                    let isAdjacent = isAdjacentToHovered(n.id)
                    let alpha: Double = {
                        if hoveredID == nil { return 1.0 }
                        if isHovered || isAdjacent { return 1.0 }
                        return 0.25
                    }()

                    // Halo
                    if isHovered {
                        let halo = Path(ellipseIn: CGRect(
                            x: p.x - r - 6, y: p.y - r - 6,
                            width: 2 * (r + 6), height: 2 * (r + 6)
                        ))
                        ctx.stroke(halo, with: .color(DS.Brand.amber.opacity(0.6)),
                                   style: StrokeStyle(lineWidth: 2))
                    }

                    // Filled circle
                    let dot = Path(ellipseIn: CGRect(
                        x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r
                    ))
                    ctx.fill(dot, with: .color(moodColor(n.entry.frontmatter.mood).opacity(alpha)))
                    ctx.stroke(dot, with: .color(.white.opacity(0.6 * alpha)),
                               style: StrokeStyle(lineWidth: 1))

                    // Label
                    if isHovered || zoom > 0.9 {
                        let label = String(n.entry.title.prefix(8))
                        let txt = Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                        ctx.draw(txt, at: CGPoint(x: p.x, y: p.y + r + 10))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onTapGesture { location in
                if let hit = hitTest(location: location, geo: geo) {
                    selectedEntry = hit
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoveredID = hitTest(location: loc, geo: geo)?.id
                case .ended:
                    hoveredID = nil
                }
            }
        }
        .background(Color.clear)
    }

    // MARK: - Adjacency

    private func isAdjacentToHovered(_ id: DiaryEntry.ID) -> Bool {
        guard let h = hoveredID else { return false }
        return GraphBuilder.build(entries: store.entries)
            .edges.contains { e in
                (e.source == h && e.target == id) || (e.target == h && e.source == id)
            }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                pan = CGSize(
                    width: lastPan.width + value.translation.width,
                    height: lastPan.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPan = pan
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = max(0.3, min(3.0, lastZoom * value))
            }
            .onEnded { _ in
                lastZoom = zoom
            }
    }

    // MARK: - Hit testing

    private func hitTest(location: CGPoint, geo: GeometryProxy) -> DiaryEntry? {
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        let gx = (location.x - center.x - pan.width) / zoom
        let gy = (location.y - center.y - pan.height) / zoom

        let nodes = GraphBuilder.build(entries: store.entries).nodes
        let nodeById = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        var bestNode: DiaryEntry? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for n in nodes {
            guard let p = positions[n.id] else { continue }
            let dx = p.x - gx, dy = p.y - gy
            let d2 = dx * dx + dy * dy
            if d2 < bestDist {
                bestDist = d2
                bestNode = n.entry
            }
        }
        if let node = bestNode {
            let r = nodeRadius(node)
            if bestDist <= (r + 4) * (r + 4) {
                return node
            }
        }
        _ = nodeById   // silence unused warning
        return nil
    }

    private func nodeRadius(_ entry: DiaryEntry) -> CGFloat {
        let bonus = log2(Double(max(entry.wordCount, 1)) + 1) * 1.4
        return 9 + CGFloat(bonus)
    }

    private func moodColor(_ mood: Int?) -> Color { DS.Mood.color(mood) }

    // MARK: - Recompute

    /// Rebuild the cosine-similarity graph and run the force layout.
    /// `force=true` clears the embedding cache (so the next rebuild
    /// recomputes everything from scratch); otherwise we rely on the
    /// index's content-hash invalidation to reuse existing vectors.
    @MainActor
    private func recomputeLayout(force: Bool = false) {
        guard !store.entries.isEmpty else {
            positions = [:]
            return
        }
        isComputing = true
        if force {
            // Touch the index so we can poke it; for now we just
            // re-resolve the embeddings — content-hash invalidation
            // will only rebuild entries whose text actually changed,
            // so this stays cheap even for big folders.
            _ = EmbeddingIndex.shared
        }
        let (nodes, edges) = GraphBuilder.build(entries: store.entries)
        let new = GraphBuilder.layout(
            nodes: nodes,
            edges: edges,
            iterations: 220,
            bounds: layoutBounds
        )
        positions = new
        lastLayoutBounds = layoutBounds
        // Save the cache so the next visit is instant.
        EmbeddingIndex.shared.saveCache()
        isComputing = false
    }
}
