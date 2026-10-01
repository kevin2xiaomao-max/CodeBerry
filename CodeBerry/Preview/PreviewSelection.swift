import Foundation

// MARK: - M3 Code ↔ Preview 双向定位
//
// Every rendered node carries a PreviewSourceInfo (file/line/UTF-8 offsets,
// §三). Two directions:
//
//   Preview → Code: tap a node → its source range (already in 3.0 via
//                   inspector.selectedID; here as a pure lookup).
//   Code → Preview: cursor line in the editor → deepest node whose source
//                   range contains that line → highlight on canvas.
//
// Pure functions over [PreviewViewNode]; the canvas/editor wire them up.

enum PreviewSelection {
    /// All nodes in the tree, depth-first (parents before children).
    static func allNodes(_ nodes: [PreviewViewNode]) -> [PreviewViewNode] {
        var out: [PreviewViewNode] = []
        func walk(_ node: PreviewViewNode) {
            out.append(node)
            for child in children(of: node) { walk(child) }
        }
        for n in nodes { walk(n) }
        return out
    }

    static func children(of node: PreviewViewNode) -> [PreviewViewNode] {
        var out: [PreviewViewNode] = []
        switch node.kind {
        case .stack(_, _, _, let c): out += c
        case .button(let label, _): out += label
        case .list(let c): out += c
        case .group(let c): out += c
        default: break
        }
        // Overlay content lives in a modifier, not in Kind.
        for m in node.modifiers {
            if case .overlay(let c) = m { out += c }
        }
        return out
    }

    /// Preview → Code: find the node by its stable nodeID.
    static func sourceInfo(for nodeID: String, in nodes: [PreviewViewNode]) -> PreviewSourceInfo? {
        allNodes(nodes).first { $0.source?.nodeID == nodeID }?.source
    }

    /// Code → Preview: deepest node whose source range contains the line.
    /// Deepest wins so a Text inside a VStack selects the Text; ties break
    /// toward the node starting closest to the cursor line.
    static func nodeID(atLine line: Int, in nodes: [PreviewViewNode]) -> String? {
        let cands = allNodes(nodes).filter { ($0.source?.line ?? Int.max) <= line }
        let best = cands.max { a, b in
            let da = depthOf(a, in: nodes), db = depthOf(b, in: nodes)
            if da != db { return da < db }
            return (a.source?.line ?? 0) < (b.source?.line ?? 0)
        }
        return best?.source?.nodeID
    }

    private static func depthOf(_ target: PreviewViewNode, in nodes: [PreviewViewNode]) -> Int {
        func walk(_ node: PreviewViewNode, depth: Int) -> Int? {
            if node.source?.nodeID == target.source?.nodeID
                && node.source != nil { return depth }
            for child in children(of: node) {
                if let d = walk(child, depth: depth + 1) { return d }
            }
            return nil
        }
        for n in nodes { if let d = walk(n, depth: 0) { return d } }
        return -1
    }

    /// Nodes on the path from the root to the node (for breadcrumb UI).
    static func path(to nodeID: String, in nodes: [PreviewViewNode]) -> [PreviewViewNode] {
        func walk(_ node: PreviewViewNode) -> [PreviewViewNode]? {
            if node.source?.nodeID == nodeID { return [node] }
            for child in children(of: node) {
                if let rest = walk(child) { return [node] + rest }
            }
            return nil
        }
        for n in nodes { if let p = walk(n) { return p } }
        return []
    }
}
