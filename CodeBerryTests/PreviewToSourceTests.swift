import XCTest
@testable import CodeBerry

/// §三十九: PreviewToSource — 画布点选节点 → 源码位置 (Preview → Code).
final class PreviewToSourceTests: XCTestCase {
    private func tree() -> [PreviewViewNode] {
        let text = PreviewViewNode(
            kind: .text("hello"),
            source: PreviewSourceInfo(file: "HomeView.swift", line: 5, startOffset: 100, endOffset: 120))
        return [PreviewViewNode(
            kind: .stack(.vertical, alignment: nil, spacing: nil, children: [text]),
            source: PreviewSourceInfo(file: "HomeView.swift", line: 4, startOffset: 80, endOffset: 240))]
    }

    func testNodeIDToSourceInfo() {
        let info = PreviewSelection.sourceInfo(for: "HomeView.swift@100", in: tree())
        XCTAssertEqual(info?.file, "HomeView.swift")
        XCTAssertEqual(info?.line, 5)
        XCTAssertEqual(info?.startOffset, 100)
        XCTAssertEqual(info?.endOffset, 120)
    }

    func testUnknownNodeIDReturnsNil() {
        XCTAssertNil(PreviewSelection.sourceInfo(for: "Nope.swift@1", in: tree()))
    }

    func testNodeWithoutSourceIsSkipped() {
        var nodes = tree()
        nodes.append(PreviewViewNode(kind: .spacer))  // source == nil
        // spacer 没有 nodeID, 不应被 sourceInfo 找到, 也不影响其他节点.
        // tree() = stack + text = 2, + spacer = 3.
        XCTAssertEqual(PreviewSelection.allNodes(nodes).count, 3)
        XCTAssertNotNil(PreviewSelection.sourceInfo(for: "HomeView.swift@100", in: nodes))
    }

    func testRoundTrip() {
        // Preview → Code → Preview 闭环: 点选 text 得 line 5, line 5 跳回 text.
        let nodes = tree()
        let info = PreviewSelection.sourceInfo(for: "HomeView.swift@100", in: nodes)!
        let back = PreviewSelection.nodeID(atLine: info.line, in: nodes)
        XCTAssertEqual(back, "HomeView.swift@100")
    }
}
