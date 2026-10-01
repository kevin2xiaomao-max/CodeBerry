import XCTest
@testable import CodeBerry

/// 4.0.2 P0-5: SwiftUI built-ins the old engine rendered as `[?]` —
/// TabView / ToolbarItem / ContentUnavailableView / GroupBox / NavigationLink /
/// LazyVGrid / LazyHGrid / GridItem / AnyView / EmptyView / GeometryReader /
/// safeAreaPadding / ScrollViewReader / Form / Link — must now approximate
/// instead of bailing out.
final class PreviewBuiltinComponentsTests: XCTestCase {

    private func render(_ body: String) throws -> (texts: [String], evaluator: PreviewEvaluator) {
        let source = """
        import SwiftUI
        struct Home: View {
            var body: some View {
        \(body)
            }
        }
        """
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        let nodes = try evaluator.renderRoot()

        var texts: [String] = []
        var sawUnsupported = false
        func walk(_ nodes: [PreviewViewNode]) {
            for n in nodes {
                switch n.kind {
                case .text(let s): texts.append(s)
                case .stack(_, _, _, let c): walk(c)
                case .group(let c): walk(c)
                case .list(let c): walk(c)
                case .unsupported: sawUnsupported = true
                default: break
                }
            }
        }
        walk(nodes)
        XCTAssertFalse(sawUnsupported, "no [?] for built-ins in: \(body)")
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "no errors in: \(body), got: \(errors.map(\.message))")
        return (texts, evaluator)
    }

    func testTabViewRendersPages() throws {
        let (texts, _) = try render("""
            TabView {
                Text("page-a")
                Text("page-b")
            }
            """)
        XCTAssertTrue(texts.contains("page-a") && texts.contains("page-b"))
    }

    func testNavigationLinkRendersLabel() throws {
        let (texts, _) = try render("""
            NavigationLink("Go", destination: Text("detail"))
            """)
        XCTAssertTrue(texts.contains("Go"))
        XCTAssertFalse(texts.contains("detail"), "destination is not preview content")
    }

    func testNavigationLinkTrailingLabel() throws {
        let (texts, _) = try render("""
            NavigationLink { Text("tap-me") } destination: { Text("detail") }
            """)
        XCTAssertTrue(texts.contains("tap-me"))
    }

    func testLazyGridsApproximateAsStacks() throws {
        let (vTexts, _) = try render("""
            LazyVGrid(columns: [GridItem(.flexible())]) { Text("cell") }
            """)
        XCTAssertTrue(vTexts.contains("cell"))
        let (hTexts, _) = try render("""
            LazyHGrid(rows: [GridItem(.flexible())]) { Text("row") }
            """)
        XCTAssertTrue(hTexts.contains("row"))
    }

    func testGridItemRendersNothingWithoutWarning() throws {
        let (_, evaluator) = try render("""
            LazyVGrid(columns: [GridItem(.fixed(80))]) { Text("x") }
            """)
        XCTAssertFalse(evaluator.diagnostics.contains {
            $0.message.contains("GridItem")
        }, "GridItem is layout metadata — no warning expected")
    }

    func testAnyViewPassesThrough() throws {
        let (texts, _) = try render(" AnyView(Text(\"wrapped\")) ")
        XCTAssertTrue(texts.contains("wrapped"))
    }

    func testEmptyViewRendersNothing() throws {
        let (texts, _) = try render(" EmptyView() ")
        XCTAssertTrue(texts.isEmpty)
    }

    func testGeometryReaderBindsParam() throws {
        let (texts, evaluator) = try render("""
            GeometryReader { geo in Text("g") }
            """)
        XCTAssertTrue(texts.contains("g"))
        XCTAssertFalse(evaluator.diagnostics.contains {
            $0.message.contains("geo")
        }, "the geometry proxy must not raise unknown-identifier")
    }

    func testScrollViewReaderBindsProxy() throws {
        let (texts, _) = try render("""
            ScrollViewReader { proxy in Text("s") }
            """)
        XCTAssertTrue(texts.contains("s"))
    }

    func testFormRendersAsList() throws {
        let (texts, _) = try render(" Form { Text(\"field\") } ")
        XCTAssertTrue(texts.contains("field"))
    }

    func testLinkRendersTitle() throws {
        let (texts, _) = try render("""
            Link("tap", destination: URL(string: "https://example.com")!)
            """)
        XCTAssertTrue(texts.contains("tap"))
    }

    func testGroupBoxRendersTitleAndContent() throws {
        let (texts, _) = try render("""
            GroupBox("Title") { Text("content") }
            """)
        XCTAssertTrue(texts.contains("Title") && texts.contains("content"))
    }

    func testContentUnavailableViewRendersTitle() throws {
        let (texts, _) = try render("""
            ContentUnavailableView("Empty", systemImage: "tray")
            """)
        XCTAssertTrue(texts.contains("Empty"))
    }

    func testSafeAreaPaddingIsSilent() throws {
        let (texts, evaluator) = try render("""
            Text("p").safeAreaPadding()
            """)
        XCTAssertTrue(texts.contains("p"))
        XCTAssertFalse(evaluator.diagnostics.contains {
            $0.message.contains("safeAreaPadding")
        }, "safeAreaPadding must not warn")
    }

    func testToolbarItemRendersInline() throws {
        let (texts, _) = try render("""
            VStack { ToolbarItem { Text("item") } }
            """)
        XCTAssertTrue(texts.contains("item"))
    }
}
