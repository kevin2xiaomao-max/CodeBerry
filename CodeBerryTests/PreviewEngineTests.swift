import XCTest
@testable import CodeBerry

/// §十八: core parser/evaluator/patch layer tests.
/// UI-level behavior (canvas, inspector sheets) is verified through the
/// §十七 fixtures; these cover the engine contract underneath.
final class PreviewEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Parse `source`, collect the document, and render the root view.
    private func render(_ source: String,
                        file: String = "ContentView.swift")
    throws -> (nodes: [PreviewViewNode], evaluator: PreviewEvaluator) {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let runtime = PreviewRuntime()
        let evaluator = PreviewEvaluator(doc: doc, runtime: runtime)
        evaluator.fileName = file
        evaluator.converter = parsed.converter
        return (try evaluator.renderRoot(), evaluator)
    }

    /// All descendant nodes of `node`, depth-first.
    private func descendants(of node: PreviewViewNode) -> [PreviewViewNode] {
        var out: [PreviewViewNode] = []
        let children: [PreviewViewNode]
        switch node.kind {
        case .stack(_, _, _, let c): children = c
        case .button(let label, _): children = label
        case .list(let c): children = c
        case .group(let c): children = c
        default: children = []
        }
        for child in children {
            out.append(child)
            out += descendants(of: child)
        }
        return out
    }

    private func allNodes(_ nodes: [PreviewViewNode]) -> [PreviewViewNode] {
        nodes + nodes.flatMap(descendants(of:))
    }

    // MARK: - computed subview

    func testComputedSubview() throws {
        let source = """
        struct ContentView: View {
            var header: some View {
                Text("Hello")
            }
            var body: some View {
                VStack {
                    header
                }
            }
        }
        """
        let (nodes, _) = try render(source)
        let texts = allNodes(nodes).compactMap { node -> String? in
            if case .text(let s) = node.kind { return s }
            return nil
        }
        XCTAssertTrue(texts.contains("Hello"), "computed subview should inline its Text")
    }

    // MARK: - helper function

    func testHelperFunction() throws {
        let source = """
        struct ContentView: View {
            func badge(_ title: String) -> some View {
                Text(title).fontWeight(.bold)
            }
            var body: some View {
                VStack {
                    badge("Hi")
                }
            }
        }
        """
        let (nodes, _) = try render(source)
        let texts = allNodes(nodes).compactMap { node -> String? in
            if case .text(let s) = node.kind { return s }
            return nil
        }
        XCTAssertTrue(texts.contains("Hi"), "helper function call should render its result")
    }

    // MARK: - cross-file view (§二)

    func testCrossFileView() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB30TestProj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cardSource = """
        struct Card: View {
            var body: some View {
                Text("from-card")
            }
        }
        """
        let homeSource = """
        struct Home: View {
            var body: some View {
                VStack {
                    Card()
                }
            }
        }
        """
        try cardSource.write(to: root.appendingPathComponent("Card.swift"),
                             atomically: true, encoding: .utf8)
        try homeSource.write(to: root.appendingPathComponent("Home.swift"),
                             atomically: true, encoding: .utf8)

        let index = PreviewProjectIndex()
        index.update(projectRoot: root,
                     projectName: "TestProj",
                     currentPath: "TestProj/Home.swift",
                     currentSource: homeSource,
                     readFile: { path in
                        let rel = path.hasPrefix("TestProj/")
                            ? String(path.dropFirst("TestProj/".count)) : path
                        return try? String(contentsOf: root.appendingPathComponent(rel),
                                            encoding: .utf8)
                     })
        XCTAssertNotNil(index.viewsByName["Card"], "index should see Card.swift")

        let engine = PreviewEngine(source: homeSource)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let runtime = PreviewRuntime()
        let evaluator = PreviewEvaluator(doc: doc, runtime: runtime)
        evaluator.converter = parsed.converter
        evaluator.projectIndex = index
        let nodes = try evaluator.renderRoot()
        let texts = allNodes(nodes).compactMap { node -> String? in
            if case .text(let s) = node.kind { return s }
            return nil
        }
        XCTAssertTrue(texts.contains("from-card"),
                      "cross-file view should resolve through the project index")
    }

    // MARK: - background in shape

    func testBackgroundInShape() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("x").background(RoundedRectangle(cornerRadius: 8).fill(.blue))
            }
        }
        """
        let (nodes, _) = try render(source)
        let hasShapeBG = allNodes(nodes).contains { node in
            node.modifiers.contains { if case .backgroundShape = $0 { return true }; return false }
        }
        XCTAssertTrue(hasShapeBG, ".background(shape.fill()) should become backgroundShape")
    }

    // MARK: - overlay

    func testOverlay() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("base").overlay(Text("badge"))
            }
        }
        """
        let (nodes, _) = try render(source)
        let overlays = allNodes(nodes).flatMap { node in
            node.modifiers.compactMap { mod -> [PreviewViewNode]? in
                if case .overlay(let c) = mod { return c }
                return nil
            }
        }
        let texts = allNodes(overlays).compactMap { node -> String? in
            if case .text(let s) = node.kind { return s }
            return nil
        }
        XCTAssertTrue(texts.contains("badge"), ".overlay content should be captured")
    }

    // MARK: - font chain

    func testFontChain() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("x").font(.system(size: 20, weight: .bold))
            }
        }
        """
        let (nodes, _) = try render(source)
        let hasFont = allNodes(nodes).contains { node in
            node.modifiers.contains { if case .font = $0 { return true }; return false }
        }
        XCTAssertTrue(hasFont, ".font(.system(size:weight:)) should record a font op")
    }

    // MARK: - frame min/max

    func testFrameMinMax() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("x").frame(minHeight: 44, maxWidth: .infinity)
            }
        }
        """
        let (nodes, _) = try render(source)
        let frames = allNodes(nodes).flatMap { $0.modifiers }.compactMap { mod -> (Double?, Double?)? in
            if case .frame(_, _, _, let minH, let maxW, _, _) = mod { return (minH, maxW) }
            return nil
        }
        XCTAssertFalse(frames.isEmpty, "frame op should be recorded")
        XCTAssertEqual(frames[0].0, 44, "minHeight should survive")
        XCTAssertNotNil(frames[0].1, "maxWidth should survive")
    }

    // MARK: - state button

    func testStateButton() throws {
        let source = """
        struct ContentView: View {
            @State private var on = false
            var body: some View {
                Button("Toggle") { on.toggle() }
            }
        }
        """
        let (nodes, evaluator) = try render(source)
        let action: (() -> Void)? = allNodes(nodes).compactMap { node in
            if case .button(_, let action) = node.kind { return action }
            return nil
        }.first
        let toggle = try XCTUnwrap(action, "button node should carry an action")
        XCTAssertEqual(evaluator.runtime.boolValue("ContentView.on"), false)
        toggle()
        XCTAssertEqual(evaluator.runtime.boolValue("ContentView.on"), true,
                       "tapping the button should flip the interpreted @State")
        toggle()
        XCTAssertEqual(evaluator.runtime.boolValue("ContentView.on"), false)
    }

    // MARK: - diagnostics (§十一)

    func testDiagnosticsError() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    undefinedThing
                }
            }
        }
        """
        let (_, evaluator) = try render(source)
        XCTAssertTrue(evaluator.diagnostics.contains { $0.severity == .error },
                      "unknown identifier should be an error diagnostic")
    }

    func testDiagnosticsWarning() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hi")
                42
            }
        }
        """
        let (_, evaluator) = try render(source)
        XCTAssertTrue(evaluator.diagnostics.contains { $0.severity == .warning },
                      "non-view expression in body should warn")
    }

    func testDiagnosticsClean() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hi")
            }
        }
        """
        let (_, evaluator) = try render(source)
        XCTAssertFalse(evaluator.diagnostics.contains { $0.severity == .error },
                       "clean source should produce no errors")
    }

    // MARK: - source range metadata (§三)

    func testSourceRangeMetadata() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let (nodes, _) = try render(source)
        let texts = allNodes(nodes).filter {
            if case .text = $0.kind { return true }
            return false
        }
        let info = try XCTUnwrap(texts.first?.source)
        XCTAssertEqual(info.line, 3, "Text node should map to source line 3")
        XCTAssertEqual(info.file, "ContentView.swift")
        XCTAssertTrue(info.startOffset < info.endOffset)
        XCTAssertFalse(info.nodeID.isEmpty)
        XCTAssertTrue(info.nodeID.contains("@"))
    }

    // MARK: - patch generation (§九)

    func testPatchGeneration() throws {
        let old = "line1\nline2\nline3\n"
        let new = "line1\nline2 changed\nline3\n"
        let diff = PreviewPatch.unifiedDiff(oldText: old, newText: new, fileName: "F.swift")
        XCTAssertTrue(diff.contains("---"), "diff should have --- header")
        XCTAssertTrue(diff.contains("+++"), "diff should have +++ header")
        XCTAssertTrue(diff.contains("@@"), "diff should have a hunk header")
        XCTAssertTrue(diff.contains("-line2"), "diff should contain the removed line")
        XCTAssertTrue(diff.contains("+line2 changed"), "diff should contain the added line")

        let url = try XCTUnwrap(PreviewPatch.patchFileURL(diff: diff, fileName: "F.swift"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let roundTrip = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(roundTrip, diff)
    }

    // MARK: - localization fallback (§一)

    func testLocalizationFallback() throws {
        let l10n = L10nService.shared
        let previous = l10n.language
        defer { l10n.language = previous }

        l10n.language = .english
        XCTAssertEqual(l10n.t(.preview), "Preview")
        l10n.language = .zhHans
        XCTAssertEqual(l10n.t(.preview), "预览")

        // No key may fall back to its rawValue: every key needs a translation.
        for key in L10nKey.allCases {
            XCTAssertNotEqual(l10n.t(key), key.rawValue, "missing translation for \(key)")
        }
    }
}
