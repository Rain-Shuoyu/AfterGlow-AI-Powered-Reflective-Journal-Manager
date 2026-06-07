import SwiftUI

struct InsightGraphView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var extractions: [DiaryEntry.ID: ExtractedEntities] = [:]
    @State private var isExtracting: Bool = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var extractionError: String?
    @State private var positions: [DiaryEntry.ID: CGPoint] = [:]
    @State private var lastLayoutBounds: CGSize = .zero
    @State private var selectedEntry: DiaryEntry?

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
        .onAppear { loadCached() }
        .onChange(of: store.entries) { _, _ in loadCached() }
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
            if isExtracting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("抽取中 \(progress.done)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await runExtraction(force: true) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(extractions.isEmpty ? "生成关系" : "重新抽取")
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .disabled(store.entries.isEmpty || settingsStore.settings.apiKey.isEmpty)
            }
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.m)
    }

    private var headerSubtitle: String {
        if store.entries.isEmpty { return "选目录后开始" }
        if isExtracting { return "正在调用 LLM 抽取实体…" }
        if extractions.isEmpty { return "点「生成关系」开始抽取" }
        let edges = GraphBuilder.build(entries: store.entries, extractions: extractions).edges
        return "\(extractions.count) 节点 · \(edges.count) 边"
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
        } else if extractions.isEmpty && !isExtracting {
            placeholder(
                icon: "wand.and.stars",
                title: settingsStore.settings.apiKey.isEmpty
                    ? "请先到「设置」页填入 API Key"
                    : "点「生成关系」按钮让 LLM 抽取实体",
                subtitle: "每篇日记大约 1~2 秒"
            )
        } else if let err = extractionError {
            placeholder(icon: "exclamationmark.triangle", title: "抽取失败", subtitle: err)
        } else if positions.isEmpty {
            // Have extractions but layout hasn't run yet — run it now.
            Color.clear
                .onAppear { recomputeLayout() }
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
                for e in GraphBuilder.build(entries: store.entries, extractions: extractions).edges {
                    guard let a = positions[e.source], let b = positions[e.target] else { continue }
                    let isHighlighted = (hoveredID == e.source || hoveredID == e.target)
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    let baseWidth: CGFloat = 0.5 + CGFloat(e.weight) * 0.7
                    ctx.stroke(
                        path,
                        with: .color(isHighlighted ? .accentColor.opacity(0.85) : .secondary.opacity(0.25)),
                        style: StrokeStyle(lineWidth: baseWidth, lineCap: .round)
                    )
                }

                // Draw nodes
                for n in GraphBuilder.build(entries: store.entries, extractions: extractions).nodes {
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
                        ctx.stroke(halo, with: .color(.accentColor.opacity(0.5)),
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
        return GraphBuilder.build(entries: store.entries, extractions: extractions)
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

        let nodes = GraphBuilder.build(entries: store.entries, extractions: extractions).nodes
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

    private func moodColor(_ mood: Int?) -> Color {
        switch mood {
        case 1: return .red
        case 2: return .orange
        case 3: return .gray
        case 4: return .green
        case 5: return .mint
        default: return .accentColor
        }
    }

    // MARK: - Extraction

    private func loadCached() {
        let cached = EntityExtractor.shared.cached(entries: store.entries)
        extractions = cached
        recomputeLayout()
    }

    @MainActor
    private func runExtraction(force: Bool) async {
        guard !store.entries.isEmpty else { return }
        guard !settingsStore.settings.apiKey.isEmpty else {
            extractionError = "请先到「设置」页填入 API Key"
            return
        }
        isExtracting = true
        extractionError = nil
        progress = (0, store.entries.count)
        defer { isExtracting = false }

        do {
            let results = try await EntityExtractor.shared.extractAll(
                entries: store.entries,
                settings: settingsStore.settings,
                model: settingsStore.settings.model,
                onProgress: { done, total in
                    progress = (done, total)
                }
            )
            extractions = results
            recomputeLayout()
        } catch {
            extractionError = error.localizedDescription
        }
    }

    /// Run the force-directed layout with the current extractions and save
    /// positions to state. Always re-runs after extraction so the saved state
    /// matches the latest data.
    @MainActor
    private func recomputeLayout() {
        guard !store.entries.isEmpty else {
            positions = [:]
            return
        }
        let (nodes, edges) = GraphBuilder.build(entries: store.entries, extractions: extractions)
        let new = GraphBuilder.layout(
            nodes: nodes,
            edges: edges,
            iterations: 220,
            bounds: layoutBounds
        )
        positions = new
        lastLayoutBounds = layoutBounds
    }
}
