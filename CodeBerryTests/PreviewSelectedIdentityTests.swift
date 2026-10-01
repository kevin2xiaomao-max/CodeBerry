import XCTest
@testable import CodeBerry

/// 4.0.3 S8 (P0-F): Selected Preview Identity.
///
/// The selected view threads end to end —
/// PreviewCandidate.viewName → canvas → IncrementalPreview →
/// PreviewEvaluator.renderRoot(targetView:) — and `viewOrder.first` is
/// never a silent default.
final class PreviewSelectedIdentityTests: XCTestCase {

    private let twoViews = """
        import SwiftUI
        struct HomeView: View {
            var body: some View { Text("HOME_ROOT") }
        }
        struct SubView: View {
            var body: some View { Text("SUB_ROOT") }
        }
        """

    private func texts(in nodes: [PreviewViewNode]) -> [String] {
        var out: [String] = []
        for node in nodes {
            if case .text(let t) = node.kind { out.append(t) }
            switch node.kind {
            case .stack(_, _, _, let c), .list(let c), .group(let c): out += texts(in: c)
            case .button(let label, _): out += texts(in: label)
            default: break
            }
        }
        return out
    }

    private func evaluate(targetView: String?) -> (nodes: [PreviewViewNode],
                                                  diagnostics: [PreviewDiagnostic]) {
        var cache = IncrementalPreview.Cache()
        let result = IncrementalPreview.evaluate(
            source: twoViews,
            fileName: "TwoViews.swift",
            cache: &cache,
            runtime: PreviewRuntime(),
            projectIndex: nil,
            mockStore: nil,
            targetView: targetView)
        return (result.nodes, result.diagnostics)
    }

    /// Selecting HomeView renders HomeView as root.
    func testSelectHomeViewRendersHomeView() {
        let (nodes, _) = evaluate(targetView: "HomeView")
        let t = texts(in: nodes)
        XCTAssertTrue(t.contains("HOME_ROOT"), "\(t)")
        XCTAssertFalse(t.contains("SUB_ROOT"), "\(t)")
    }

    /// Selecting the sub-view renders the sub-view as root.
    func testSelectSubViewRendersSubView() {
        let (nodes, _) = evaluate(targetView: "SubView")
        let t = texts(in: nodes)
        XCTAssertTrue(t.contains("SUB_ROOT"), "\(t)")
        XCTAssertFalse(t.contains("HOME_ROOT"), "\(t)")
    }

    /// No `viewOrder.first` default: multi-view + no target warns and
    /// renders nothing (never silently picks the first view).
    func testNoSilentFirstViewDefault() {
        let (nodes, diagnostics) = evaluate(targetView: nil)
        XCTAssertTrue(nodes.isEmpty, "must not render without an explicit target")
        XCTAssertTrue(diagnostics.contains { $0.key == .diagNoTargetView },
                      "\(diagnostics.map(\.message))")
    }

    /// An unknown target is an honest error, not a silent fallback.
    func testUnknownTargetErrors() {
        let (nodes, _) = evaluate(targetView: "NopeView")
        XCTAssertTrue(nodes.isEmpty)
    }

    /// Single-view files stay unambiguous without a target.
    func testSingleViewNeedsNoTarget() {
        var cache = IncrementalPreview.Cache()
        let result = IncrementalPreview.evaluate(
            source: "import SwiftUI\nstruct Only: View { var body: some View { Text(\"ONLY\") } }",
            fileName: "Only.swift",
            cache: &cache,
            runtime: PreviewRuntime(),
            projectIndex: nil,
            mockStore: nil)
        XCTAssertTrue(texts(in: result.nodes).contains("ONLY"))
    }

    /// Cache keys differ per target — a selection change can't hit a
    /// stale entry rendered for another view.
    func testCacheKeyIncludesTarget() throws {
        let engine = PreviewEngine(source: twoViews)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let home = IncrementalPreview.cacheKey(doc: doc, fileName: "T.swift", targetView: "HomeView")
        let sub = IncrementalPreview.cacheKey(doc: doc, fileName: "T.swift", targetView: "SubView")
        let none = IncrementalPreview.cacheKey(doc: doc, fileName: "T.swift", targetView: nil)
        XCTAssertNotEqual(home.key, sub.key)
        XCTAssertNotEqual(home.key, none.key)
    }
}
