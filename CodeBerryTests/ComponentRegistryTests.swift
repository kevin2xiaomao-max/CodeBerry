import XCTest
@testable import CodeBerry

/// §三十九: ComponentRegistry — 四注册表 + 不改 evaluator core 即可扩展.
final class ComponentRegistryTests: XCTestCase {
    func testBuiltInViewLookup() {
        let e = ViewRegistry.entry(for: "VStack")
        XCTAssertNotNil(e)
        XCTAssertEqual(e?.supportLevel, .supported)
        XCTAssertTrue(e?.acceptedArgs.contains("spacing") == true)
    }

    func testApproximateLevels() {
        XCTAssertEqual(ViewRegistry.entry(for: "LazyVStack")?.supportLevel, .approximate)
        XCTAssertEqual(ViewRegistry.entry(for: "NavigationStack")?.supportLevel, .approximate)
    }

    func testFutureComponentsListedAsUnsupported() {
        // §15 点名的未来组件: 注册表里有, evaluator core 不用改.
        for s in ["Grid", "Menu", "Picker", "Gauge"] {
            XCTAssertEqual(ViewRegistry.entry(for: s)?.supportLevel, .unsupported, s)
        }
    }

    func testModifierRegistry() {
        XCTAssertEqual(ModifierRegistry.entry(for: "padding")?.supportLevel, .supported)
        XCTAssertEqual(ModifierRegistry.entry(for: "minimumScaleFactor")?.supportLevel, .cosmeticIgnore)
    }

    func testShapeAndStyleRegistries() {
        XCTAssertNotNil(ShapeRegistry.entry(for: "Circle"))
        XCTAssertEqual(ShapeRegistry.entry(for: "Path")?.supportLevel, .unsupported)
        XCTAssertNotNil(ComponentRegistry.entry(for: "LinearGradient"))
    }

    func testDashboardCoversSpecExample() {
        // §24 示例行: Text/VStack ✅, @Environment/Charts 🟡, @Query/SwiftData 🔴.
        // Shapes are intentionally dual-listed (view + shape registries); keep first.
        let items = Dictionary(ComponentRegistry.dashboardItems().map { ($0.symbol, $0) },
                               uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(items["Text"]?.supportLevel, .supported)
        XCTAssertEqual(items["VStack"]?.supportLevel, .supported)
        XCTAssertEqual(items["Grid"]?.supportLevel, .unsupported)
        // Dashboard 非空且按 symbol 排序.
        let symbols = ComponentRegistry.dashboardItems().map(\.symbol)
        XCTAssertEqual(symbols, symbols.sorted())
        XCTAssertGreaterThan(symbols.count, 30)
    }

    func testCustomViewRegistrationRendersWithoutCoreChange() throws {
        // 注册一个自定义 view, 走 evaluator 的 hook 真实渲染.
        ViewRegistry.register(symbol: "TestBadge_M3", acceptedArgs: ["text"],
                              supportLevel: .supported, diagnostics: "测试徽章") { evaluator, _, args, env in
            let text = try args.first.map { try evaluator.eval($0.expr, env: env) }?.display ?? ""
            return .view(PreviewViewNode(kind: .text("badge:\(text)")))
        }
        XCTAssertTrue(ViewRegistry.isKnownView("TestBadge_M3"))

        let source = """
            import SwiftUI
            struct Root: View {
                var body: some View { TestBadge_M3(text: "hi") }
            }
            """
        let engine = PreviewEngine(source: source)
        let doc = try engine.parse()
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        let nodes = try evaluator.renderRoot()
        XCTAssertEqual(nodes.count, 1)
        if case .text(let t) = nodes[0].kind {
            XCTAssertEqual(t, "badge:hi")
        } else {
            XCTFail("custom view did not render, got \(nodes[0].kind)")
        }
        // 未注册的自定义 view 仍走 unsupported 占位.
        let source2 = """
            import SwiftUI
            struct Root: View {
                var body: some View { NeverRegistered_M3() }
            }
            """
        let doc2 = try PreviewEngine(source: source2).parse()
        let nodes2 = try PreviewEvaluator(doc: doc2, runtime: PreviewRuntime()).renderRoot()
        if case .unsupported(let name) = nodes2[0].kind {
            XCTAssertEqual(name, "NeverRegistered_M3")
        } else {
            XCTFail("expected unsupported placeholder")
        }
    }
}
