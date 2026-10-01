import XCTest
@testable import CodeBerry

/// §三十九: SourceToPreview — 编辑器光标行 → 画布节点 (Code → Preview).
final class SourceToPreviewTests: XCTestCase {
    private func tree() -> [PreviewViewNode] {
        // 手工构造带 source info 的节点树 (行号模拟真实 converter 输出).
        let text = PreviewViewNode(
            kind: .text("hello"),
            source: PreviewSourceInfo(file: "HomeView.swift", line: 5, startOffset: 100, endOffset: 120))
        let button = PreviewViewNode(
            kind: .button(label: [PreviewViewNode(
                kind: .text("tap"),
                source: PreviewSourceInfo(file: "HomeView.swift", line: 8, startOffset: 200, endOffset: 210))],
                          action: nil),
            source: PreviewSourceInfo(file: "HomeView.swift", line: 7, startOffset: 180, endOffset: 230))
        return [PreviewViewNode(
            kind: .stack(.vertical, alignment: nil, spacing: nil, children: [text, button]),
            source: PreviewSourceInfo(file: "HomeView.swift", line: 4, startOffset: 80, endOffset: 240))]
    }

    func testCursorOnTextSelectsText() {
        let id = PreviewSelection.nodeID(atLine: 5, in: tree())
        XCTAssertEqual(id, "HomeView.swift@100")
    }

    func testCursorOnButtonLabelSelectsDeepestNode() {
        // 第 8 行: button(7行起) 和 label text(8行) 都包含 → 选最深的 text.
        let id = PreviewSelection.nodeID(atLine: 8, in: tree())
        XCTAssertEqual(id, "HomeView.swift@200")
    }

    func testCursorOnStackLineSelectsStack() {
        let id = PreviewSelection.nodeID(atLine: 4, in: tree())
        XCTAssertEqual(id, "HomeView.swift@80")
    }

    func testNoNodeBeforeFirstLine() {
        XCTAssertNil(PreviewSelection.nodeID(atLine: 1, in: tree()))
    }

    func testPathToNode() {
        let path = PreviewSelection.path(to: "HomeView.swift@200", in: tree())
        XCTAssertEqual(path.count, 3)  // stack → button → text
        XCTAssertEqual(path.last?.source?.nodeID, "HomeView.swift@200")
    }

    func testAllNodesDepthFirst() {
        let all = PreviewSelection.allNodes(tree())
        XCTAssertEqual(all.count, 4)
        if case .stack = all[0].kind {} else { XCTFail("parents before children") }
    }
}
