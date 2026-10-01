import XCTest
@testable import CodeBerry

/// 4.0.2 P1-8: external packages (Charts/…) are marked "not executed" and
/// must never block the rest of the page.
final class PreviewExternalPackageTests: XCTestCase {

    private func render(_ source: String, targetView: String? = nil) throws -> (texts: [String],
                                                    externals: [(package: String, symbol: String)],
                                                    unsupported: [String],
                                                    evaluator: PreviewEvaluator) {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        // 4.0.3 S8 (P0-F): the target view is explicit; multi-view sources
        // never silently render viewOrder.first.
        let nodes = try evaluator.renderRoot(targetView: targetView)

        var texts: [String] = []
        var externals: [(String, String)] = []
        var unsupported: [String] = []
        func walk(_ nodes: [PreviewViewNode]) {
            for n in nodes {
                switch n.kind {
                case .text(let s): texts.append(s)
                case .stack(_, _, _, let c): walk(c)
                case .group(let c): walk(c)
                case .list(let c): walk(c)
                case .externalPackage(let pkg, let sym): externals.append((pkg, sym))
                case .unsupported(let name): unsupported.append(name)
                default: break
                }
            }
        }
        walk(nodes)
        return (texts, externals, unsupported, evaluator)
    }

    func testChartDoesNotBlockThePage() throws {
        let (texts, externals, unsupported, evaluator) = try render("""
        import SwiftUI
        import Charts
        struct Home: View {
            var body: some View {
                VStack {
                    Text("before")
                    Chart {
                        BarMark(x: .value("Day", "Mon"), y: .value("Amount", 120))
                        LineMark(x: .value("Day", "Tue"), y: .value("Amount", 200))
                    }
                    Text("after")
                }
            }
        }
        """)
        // The page renders around the chart …
        XCTAssertTrue(texts.contains("before") && texts.contains("after"))
        // … the chart is explicitly marked "not executed" …
        XCTAssertEqual(externals.count, 1)
        XCTAssertEqual(externals.first?.package, "Charts")
        XCTAssertEqual(externals.first?.symbol, "Chart")
        // … not the generic [?] …
        XCTAssertTrue(unsupported.isEmpty)
        // … the chart content closure is never evaluated (no cascade) …
        XCTAssertEqual(evaluator.diagnostics.count, 1)
        XCTAssertEqual(evaluator.diagnostics.first?.key, .diagExternalPackageNotExecuted)
        // … and nothing errors.
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error })
    }

    func testMapKitIsMarkedNotExecuted() throws {
        let (_, externals, _, evaluator) = try render("""
        import SwiftUI
        import MapKit
        struct Home: View {
            var body: some View { Map() }
        }
        """)
        XCTAssertEqual(externals.first?.package, "MapKit")
        XCTAssertEqual(evaluator.diagnostics.first?.severity, .warning)
    }

    func testProjectDefinedViewWinsOverExternalMapping() throws {
        // A project that defines its own `Chart` view keeps it — the
        // external mapping must not shadow user code.
        // 4.0.3 S8: explicit target (the source declares two views).
        let (texts, externals, _, _) = try render("""
        import SwiftUI
        struct Chart: View {
            var body: some View { Text("my-chart") }
        }
        struct Home: View {
            var body: some View { Chart() }
        }
        """, targetView: "Home")
        XCTAssertTrue(externals.isEmpty)
        XCTAssertTrue(texts.contains("my-chart"))
    }
}
