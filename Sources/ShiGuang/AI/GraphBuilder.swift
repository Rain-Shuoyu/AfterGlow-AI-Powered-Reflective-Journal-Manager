import Foundation
import CoreGraphics

// MARK: - Graph data types

struct GraphNode: Identifiable, Hashable {
    let id: DiaryEntry.ID
    let entry: DiaryEntry
    /// Position in graph-space (before pan/zoom).
    var position: CGPoint
}

struct GraphEdge: Identifiable, Hashable {
    let id: String
    let source: DiaryEntry.ID
    let target: DiaryEntry.ID
    /// Cosine similarity in [0, 1] between the two entries' embeddings.
    /// Used to scale the line width and to filter out unrelated pairs.
    let weight: Double
    /// Number of entries in the shared topical neighbourhood (used for
    /// the "active" neighbour set in the hover UI). Cheap to compute
    /// from the edge list itself.
    let sharedNeighborCount: Int
}

// MARK: - Builder

/// Builds the relationship graph from diary entries.
///
/// Edges are derived from **cosine similarity over Apple NLEmbedding**
/// vectors — the same `EmbeddingIndex` used by the AI chat indexer.
/// Two entries are connected when their content is semantically related
/// (not just sharing exact words). This is the right call for a diary
/// graph: phrase-matching misses paraphrases, mood echoes, and
/// recurring themes that use different vocabulary on different days.
enum GraphBuilder {

    /// Cosine threshold below which a pair is considered unrelated and
    /// gets no edge. Tuned for `NLEmbedding.wordEmbedding(.simplifiedChinese)`
    /// bag-of-words vectors, where strongly related Chinese diary
    /// entries typically land in 0.50–0.80, mildly related ones in
    /// 0.20–0.45, and unrelated ones in 0.05–0.15.
    ///
    /// 0.50 keeps only meaningfully related pairs — most of the graph
    /// becomes tight clusters of "really about the same thing"
    /// rather than a noisy web of tenuous connections.
    static let edgeThreshold: Double = 0.50

    /// Build the graph. Synchronous because the underlying
    /// `EmbeddingIndex.embeddingForEntry` reads from an in-memory cache
    /// (persisted to disk) — so on warm runs the call is just a
    /// dictionary lookup + a dot product per pair.
    static func build(entries: [DiaryEntry]) -> (nodes: [GraphNode], edges: [GraphEdge]) {
        // Resolve embeddings up front. Entries without an in-vocabulary
        // token (e.g. emoji-only) won't get a vector; they're still in
        // the node list but skip the edge pass.
        var vectors: [DiaryEntry.ID: [Double]] = [:]
        for e in entries {
            if let v = EmbeddingIndex.shared.embeddingForEntry(e) {
                vectors[e.id] = v
            }
        }

        // Nodes: deterministic initial positions on a small circle;
        // the force simulation re-spaces them.
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let radius: CGFloat = max(60, CGFloat(sortedEntries.count) * 8)
        let nodes: [GraphNode] = sortedEntries.enumerated().map { idx, e in
            let n = CGFloat(max(sortedEntries.count, 1))
            let angle = (CGFloat(idx) / n) * 2 * .pi
            return GraphNode(
                id: e.id,
                entry: e,
                position: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            )
        }

        // Edges: O(N²) pairwise cosine. Two entries whose embeddings
        // are above `edgeThreshold` get a connection; the similarity
        // value becomes the edge weight (the UI scales the line
        // width off it).
        var rawEdges: [(DiaryEntry.ID, DiaryEntry.ID, Double)] = []
        let idList = Array(vectors.keys)
        for i in 0..<idList.count {
            for j in (i + 1)..<idList.count {
                let a = idList[i], b = idList[j]
                let sim = EmbeddingIndex.shared.similarity(vectors[a]!, vectors[b]!)
                if sim >= edgeThreshold {
                    rawEdges.append((a, b, sim))
                }
            }
        }

        // Pre-compute neighbour count per node (used by the UI for the
        // "highlight all neighbours on hover" effect, even though
        // that effect looks at edges directly — we expose this for
        // any future detail views / legends that want to know how
        // connected an entry is).
        var degree: [DiaryEntry.ID: Int] = [:]
        for (a, b, _) in rawEdges {
            degree[a, default: 0] += 1
            degree[b, default: 0] += 1
        }

        let edges: [GraphEdge] = rawEdges.map { (a, b, sim) in
            let key = a < b ? "\(a)-->\(b)" : "\(b)-->\(a)"
            return GraphEdge(
                id: key,
                source: a,
                target: b,
                weight: sim,
                sharedNeighborCount: min(degree[a] ?? 0, degree[b] ?? 0)
            )
        }

        return (nodes, edges)
    }

    // MARK: - Force-directed layout

    /// Run a simple spring/electrostatic force simulation. Returns a
    /// position dict keyed by `DiaryEntry.ID`.
    static func layout(
        nodes: [GraphNode],
        edges: [GraphEdge],
        iterations: Int = 220,
        bounds: CGSize = CGSize(width: 1100, height: 700)
    ) -> [DiaryEntry.ID: CGPoint] {
        guard !nodes.isEmpty else { return [:] }

        // Mutable working copy of positions
        var pos: [DiaryEntry.ID: CGPoint] = [:]
        var vel: [DiaryEntry.ID: CGPoint] = [:]
        for n in nodes {
            pos[n.id] = n.position
            vel[n.id] = .zero
        }

        // Tuned for the typical "personal journal" graph: 5–50 nodes, mostly
        // sparse with a few tight clusters. Goal is a compact cluster, not a
        // outer ring of lonely dots.
        let kRepel: CGFloat = 6500    // moderate repulsion — prevents overlap
        let kSpring: CGFloat = 0.06  // edges pull noticeably
        let restLength: CGFloat = 75 // connected nodes prefer this distance
        let kCenter: CGFloat = 0.012 // strong-ish center pull keeps graph compact
        let damping: CGFloat = 0.84
        let nodeIds = nodes.map { $0.id }
        let edgePairs: [(DiaryEntry.ID, DiaryEntry.ID)] = edges.map { ($0.source, $0.target) }

        for _ in 0..<iterations {
            // Reset forces
            var force: [DiaryEntry.ID: CGPoint] = [:]
            for id in nodeIds { force[id] = .zero }

            // Repulsion between every pair (O(N²))
            for i in 0..<nodeIds.count {
                for j in (i + 1)..<nodeIds.count {
                    let a = nodeIds[i], b = nodeIds[j]
                    let pa = pos[a]!, pb = pos[b]!
                    var dx = pa.x - pb.x, dy = pa.y - pb.y
                    var dist = sqrt(dx * dx + dy * dy)
                    if dist < 0.01 { dist = 0.01; dx = 0.6; dy = 0.4 }
                    let f = kRepel / (dist * dist)
                    let ux = dx / dist, uy = dy / dist
                    force[a]!.x += ux * f
                    force[a]!.y += uy * f
                    force[b]!.x -= ux * f
                    force[b]!.y -= uy * f
                }
            }

            // Spring attraction along edges
            for (a, b) in edgePairs {
                let pa = pos[a]!, pb = pos[b]!
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < 0.01 { continue }
                let stretch = dist - restLength
                let f = kSpring * stretch
                let ux = dx / dist, uy = dy / dist
                force[a]!.x += ux * f
                force[a]!.y += uy * f
                force[b]!.x -= ux * f
                force[b]!.y -= uy * f
            }

            // Pull toward center
            for id in nodeIds {
                let p = pos[id]!
                force[id]!.x -= p.x * kCenter
                force[id]!.y -= p.y * kCenter
            }

            // Integrate
            for id in nodeIds {
                let p = pos[id]!
                let v = vel[id]!
                let f = force[id]!
                let nv = CGPoint(x: (v.x + f.x) * damping, y: (v.y + f.y) * damping)
                vel[id] = nv
                pos[id] = CGPoint(x: p.x + nv.x, y: p.y + nv.y)
            }
        }

        // Normalize so positions fit comfortably in `bounds` (with margin)
        let margin: CGFloat = 60
        let xs = pos.values.map { $0.x }
        let ys = pos.values.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return pos }
        let rangeX = max(maxX - minX, 1)
        let rangeY = max(maxY - minY, 1)
        let scaleX = (bounds.width - 2 * margin) / rangeX
        let scaleY = (bounds.height - 2 * margin) / rangeY
        let s = min(scaleX, scaleY)
        for (id, p) in pos {
            let cx = (p.x - (minX + maxX) / 2) * s
            let cy = (p.y - (minY + maxY) / 2) * s
            pos[id] = CGPoint(x: cx, y: cy)
        }
        return pos
    }
}
