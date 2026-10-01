import XCTest
@testable import CodeBerry

/// §三十九: IncrementalPreview — 相同源码二次求值命中缓存; 改动后重建;
/// 语法错误不进缓存; debug stats 可用; reset 清空缓存.
final class IncrementalPreviewTests: XCTestCase {
    private let source = """
        import SwiftUI
        struct HomeView: View {
            var body: some View {
                VStack {
                    Text("hello")
                }
            }
        }
        """

    private func evaluate(_ source: String, cache: inout IncrementalPreview.Cache)
        -> (nodes: [PreviewViewNode], diagnostics: [PreviewDiagnostic],
            stats: IncrementalPreview.Stats, evaluator: PreviewEvaluator)
    {
        IncrementalPreview.evaluate(source: source, fileName: "HomeView.swift",
                                    cache: &cache, runtime: PreviewRuntime(),
                                    projectIndex: nil, mockStore: nil)
    }

    func testSecondEvaluateHitsCache() {
        var cache = IncrementalPreview.Cache()
        let first = evaluate(source, cache: &cache)
        XCTAssertFalse(first.nodes.isEmpty)
        XCTAssertEqual(first.stats.misses, 1)
        XCTAssertEqual(first.stats.hits, 0)

        let second = evaluate(source, cache: &cache)
        XCTAssertEqual(second.nodes.count, first.nodes.count)
        XCTAssertEqual(second.stats.hits, 1)
        XCTAssertEqual(second.stats.misses, 1)
        XCTAssertEqual(second.stats.hitRate, 0.5, accuracy: 0.001)
    }

    func testChangedSourceRebuilds() {
        var cache = IncrementalPreview.Cache()
        _ = evaluate(source, cache: &cache)
        // 只改 body 文本: AST identity 变化 → 重建, 不命中.
        let changed = source.replacingOccurrences(of: "Text(\"hello\")",
                                                  with: "Text(\"hello\").padding(16)")
        let second = evaluate(changed, cache: &cache)
        XCTAssertFalse(second.nodes.isEmpty)
        XCTAssertEqual(second.stats.hits, 0)
        XCTAssertEqual(second.stats.misses, 2)
    }

    func testParseErrorFallsBackSafely() {
        var cache = IncrementalPreview.Cache()
        let result = evaluate("struct Broken {", cache: &cache)
        XCTAssertTrue(result.nodes.isEmpty)
        // 错误不污染缓存: 之后的有效源码仍能正常求值.
        let ok = evaluate(source, cache: &cache)
        XCTAssertFalse(ok.nodes.isEmpty)
    }

    func testDebugStatsArePopulated() {
        var cache = IncrementalPreview.Cache()
        let r = evaluate(source, cache: &cache)
        XCTAssertGreaterThanOrEqual(r.stats.meanMillis, 0)
        XCTAssertEqual(r.stats.hits + r.stats.misses, 1)
    }

    func testResetClearsCache() {
        var cache = IncrementalPreview.Cache()
        _ = evaluate(source, cache: &cache)
        _ = evaluate(source, cache: &cache)
        XCTAssertEqual(cache.hits, 1)
        cache.reset()
        XCTAssertEqual(cache.hits, 0)
        XCTAssertTrue(cache.entries.isEmpty)
        let third = evaluate(source, cache: &cache)
        XCTAssertEqual(third.stats.hits, 0)
        XCTAssertEqual(third.stats.misses, 1)
    }

    func testEvaluatorCarriesFileContext() {
        var cache = IncrementalPreview.Cache()
        let r = evaluate(source, cache: &cache)
        // canvas 靠这个 evaluator 做 mockRequirements / activeViews.
        XCTAssertEqual(r.evaluator.fileName, "HomeView.swift")
        XCTAssertNotNil(r.evaluator.converter)
    }
}
