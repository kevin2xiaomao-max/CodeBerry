import XCTest
@testable import CodeBerry

/// §三十九: InspectorRewrite — modifier 安全重排 + token 感知 + 单参数重置.
final class InspectorRewriteTests: XCTestCase {
    private let source = """
        import SwiftUI
        struct Card: View {
            var body: some View {
                Text("hello")
                    .padding(8)
                    .font(.title)
                    .background(.red)
            }
        }
        """

    private var textRange: Range<Int> {
        // Text("hello")... 所在行的整体 range: 取整个 body 表达式范围.
        let start = source.distance(from: source.startIndex,
                                    to: source.range(of: "Text(\"hello\")")!.lowerBound)
        return start..<source.utf8.count
    }

    func testModifierChainOrder() {
        let chain = PreviewSourceEditor.modifierChain(in: source, range: textRange)
        // outermost-first: background, font, padding.
        XCTAssertEqual(chain, ["background", "font", "padding"])
    }

    func testAdjacentSafeSwap() {
        // 把 font 和 padding 交换: from=1(font) to=2(padding).
        guard let out = PreviewSourceEditor.reorderModifiers(source: source, range: textRange,
                                                             from: 1, to: 2) else {
            XCTFail("reorder returned nil"); return
        }
        let chain = PreviewSourceEditor.modifierChain(in: out, range: 0..<out.utf8.count)
        XCTAssertEqual(chain, ["background", "padding", "font"])
        // 语义保持: 三个 modifier 都还在.
        XCTAssertTrue(out.contains(".padding(8)"))
        XCTAssertTrue(out.contains(".font(.title)"))
        XCTAssertTrue(out.contains(".background(.red)"))
        // 结果仍可 parse.
        XCTAssertNotNil(PreviewEngine(source: out).parseTree())
    }

    func testNonAdjacentSwapRejected() {
        XCTAssertNil(PreviewSourceEditor.reorderModifiers(source: source, range: textRange,
                                                           from: 0, to: 2))
    }

    func testUnsafeModifierRejected() {
        let src = """
            import SwiftUI
            struct C: View {
                var body: some View {
                    Text("x").padding(8).task { await foo() }
                }
            }
            """
        let range = 0..<src.utf8.count
        let chain = PreviewSourceEditor.modifierChain(in: src, range: range)
        XCTAssertEqual(chain, ["task", "padding"])
        // task 不在安全集合 → 拒绝.
        XCTAssertNil(PreviewSourceEditor.reorderModifiers(source: src, range: range, from: 0, to: 1))
    }

    func testTokenReferenceDetection() {
        let known: Set<String> = ["V32Layout.sectionGap", "V32Colors.brand"]
        XCTAssertEqual(DesignTokenDetector.tokenReference(in: "V32Layout.sectionGap", knownTokens: known),
                       "V32Layout.sectionGap")
        XCTAssertEqual(DesignTokenDetector.tokenReference(in: ".padding(V32Layout.sectionGap)", knownTokens: known),
                       "V32Layout.sectionGap")
        // 框架类型不算 token.
        XCTAssertNil(DesignTokenDetector.tokenReference(in: "Color.red", knownTokens: known))
        // 不在已知集合里的 TypeName.member 不算.
        XCTAssertNil(DesignTokenDetector.tokenReference(in: "Foo.bar", knownTokens: known))
        // knownTokens 为空时用命名启发式.
        XCTAssertEqual(DesignTokenDetector.tokenReference(in: "V32Layout.sectionGap", knownTokens: []),
                       "V32Layout.sectionGap")
    }

    func testReferenceCount() {
        let files = [
            "let a = V32Layout.sectionGap\nlet b = V32Layout.sectionGap",
            "let c = V32Layout.other",
        ]
        XCTAssertEqual(DesignTokenDetector.referenceCount(of: "V32Layout.sectionGap", in: files), 2)
        // 词边界: sectionGap2 不算.
        XCTAssertEqual(DesignTokenDetector.referenceCount(of: "V32Layout.sectionGap",
                                                          in: ["let x = V32Layout.sectionGap2"]), 0)
    }

    func testResetOneParamKeepsOthers() {
        let state = PreviewInspectorState()
        let id = "f@1"
        state.setOverride({ $0.fontSize = 20; $0.opacity = 0.5 }, for: id)
        state.resetParam(.fontSize, for: id)
        let o = state.overrides[id]
        XCTAssertNil(o?.fontSize)
        XCTAssertEqual(o?.opacity, 0.5)
        // 全部清掉后 key 被移除.
        state.resetParam(.opacity, for: id)
        XCTAssertNil(state.overrides[id])
    }
}
