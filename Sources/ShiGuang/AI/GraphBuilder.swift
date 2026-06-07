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
    /// Number of shared entities (the "strength" of the connection).
    let weight: Int
    let shared: [SharedPhrase]

    struct SharedPhrase: Hashable {
        let kind: EntityKind
        let phrase: String
    }
}

// MARK: - Builder

enum GraphBuilder {
    /// Build nodes and edges from a set of entries + their LLM extractions.
    static func build(
        entries: [DiaryEntry],
        extractions: [DiaryEntry.ID: ExtractedEntities]
    ) -> (nodes: [GraphNode], edges: [GraphEdge]) {
        let entitiesByEntry: [DiaryEntry.ID: ExtractedEntities] = entries.reduce(into: [:]) { acc, e in
            if let x = extractions[e.id] { acc[e.id] = x }
        }

        // Nodes: deterministic initial positions on a circle, indexed by date order.
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let radius: CGFloat = 220
        let nodes: [GraphNode] = sortedEntries.enumerated().map { idx, e in
            let n = CGFloat(max(sortedEntries.count, 1))
            let angle = (CGFloat(idx) / n) * 2 * .pi
            return GraphNode(
                id: e.id,
                entry: e,
                position: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            )
        }

        // Edges: O(N²) pair scan with shared-entity match.
        var edges: [GraphEdge] = []
        let entryList = Array(entitiesByEntry)
        for i in 0..<entryList.count {
            for j in (i + 1)..<entryList.count {
                let (lhsID, lhsEnt) = entryList[i]
                let (rhsID, rhsEnt) = entryList[j]
                guard lhsID != rhsID else { continue }
                let shared = sharedPhrases(lhs: lhsEnt, rhs: rhsEnt)
                guard !shared.isEmpty else { continue }
                let key = lhsID < rhsID
                    ? "\(lhsID)-->\(rhsID)"
                    : "\(rhsID)-->\(lhsID)"
                edges.append(GraphEdge(
                    id: key,
                    source: lhsID,
                    target: rhsID,
                    weight: shared.count,
                    shared: shared
                ))
            }
        }
        return (nodes, edges)
    }

    private static func sharedPhrases(lhs: ExtractedEntities, rhs: ExtractedEntities) -> [GraphEdge.SharedPhrase] {
        var out: [GraphEdge.SharedPhrase] = []
        for kind in EntityKind.allCases {
            let l = Set(lhs.phrases(of: kind))
            let r = Set(rhs.phrases(of: kind))
            for phrase in l.intersection(r) {
                out.append(.init(kind: kind, phrase: phrase))
            }
        }
        return out
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

        let kRepel: CGFloat = 18000   // Coulomb constant (stronger so disconnected nodes don't collapse)
        let kSpring: CGFloat = 0.035 // Hooke constant (attraction)
        let restLength: CGFloat = 110 // ideal edge length
        let kCenter: CGFloat = 0.004 // pull-toward-center (weaker, was collapsing 10-node graphs)
        let damping: CGFloat = 0.82
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
