import XCTest
@testable import CodeBerry

/// 4.0.2 P0-3: cross-file ordinary-type resolution.
///
/// Regression context: `HomeView` reads `DemoMode.shared.isEnabled`
/// (`final class DemoMode` with `static let shared` and a `didSet` that
/// writes UserDefaults). The old engine reported an unknown-identifier
/// *error* for `DemoMode` and rendered `[?]`. Nothing may ever be executed —
/// opaque members fall back to preview defaults with an Info note.
final class PreviewCrossFileTypeResolutionTests: XCTestCase {

    private let demoModeSource = """
    final class DemoMode {
        static let shared = DemoMode()
        var isEnabled: Bool {
            didSet { UserDefaults.standard.set(isEnabled, forKey: "demo") }
        }
        private init() { self.isEnabled = false }
    }
    """

    private let catalogSource = """
    struct DemoCatalog {
        static let monthlyRevenue = 68_400.0
        static let currencyCode = "CNY"
    }
    """

    private let modeSource = """
    enum Mode {
        case demo, live
    }
    """

    /// Builds a temp project (Demo.swift + Home.swift), indexes it, and
    /// renders `homeSource` with the index attached.
    private func renderHome(_ homeSource: String,
                            demoSource: String? = nil,
                            catalog: Bool = false,
                            mode: Bool = false)
    throws -> (nodes: [PreviewViewNode], evaluator: PreviewEvaluator, index: PreviewProjectIndex) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB402Types-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try (demoSource ?? demoModeSource).write(to: root.appendingPathComponent("Demo.swift"),
                                                 atomically: true, encoding: .utf8)
        if catalog {
            try catalogSource.write(to: root.appendingPathComponent("Catalog.swift"),
                                    atomically: true, encoding: .utf8)
        }
        if mode {
            try modeSource.write(to: root.appendingPathComponent("Mode.swift"),
                                 atomically: true, encoding: .utf8)
        }
        try homeSource.write(to: root.appendingPathComponent("Home.swift"),
                             atomically: true, encoding: .utf8)

        let index = PreviewProjectIndex()
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: "Proj/Home.swift", currentSource: homeSource,
                     readFile: { path in
                        let rel = path.hasPrefix("Proj/")
                            ? String(path.dropFirst("Proj/".count)) : path
                        return try? String(contentsOf: root.appendingPathComponent(rel),
                                            encoding: .utf8)
                     })

        let engine = PreviewEngine(source: homeSource)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        evaluator.projectIndex = index
        let nodes = try evaluator.renderRoot()
        return (nodes, evaluator, index)
    }

    private func texts(in nodes: [PreviewViewNode]) -> [String] {
        var out: [String] = []
        func walk(_ nodes: [PreviewViewNode]) {
            for n in nodes {
                switch n.kind {
                case .text(let s): out.append(s)
                case .stack(_, _, _, let c): walk(c)
                case .group(let c): walk(c)
                case .list(let c): walk(c)
                default: break
                }
            }
        }
        walk(nodes)
        return out
    }

    // MARK: - DemoMode.shared.isEnabled: no error, preview default

    func testSingletonMemberUsesPreviewDefaultWithoutError() throws {
        let home = """
        struct Home: View {
            var body: some View {
                Text(DemoMode.shared.isEnabled ? "demo" : "real")
            }
        }
        """
        let (nodes, evaluator, index) = try renderHome(home)

        XCTAssertTrue(index.typesByName["DemoMode"]?.isSingleton == true,
                      "static let shared must be recognized as a singleton")
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "DemoMode must not produce errors, got: \(errors.map(\.message))")
        let infos = evaluator.diagnostics.filter { $0.severity == .info }
        XCTAssertTrue(infos.contains { $0.key == .diagTypePreviewDefault },
                      "an Info note '使用预览默认值' is expected, got: \(evaluator.diagnostics.map(\.message))")
        XCTAssertTrue(texts(in: nodes).contains("real"),
                      "isEnabled defaults to false → the false branch renders")
    }

    // MARK: - static let literals resolve to real values

    func testStaticLetLiteralResolves() throws {
        let home = """
        struct Home: View {
            var body: some View {
                Text(DemoCatalog.monthlyRevenue > 1000 ? "rich" : "poor")
            }
        }
        """
        let (nodes, evaluator, _) = try renderHome(home, catalog: true)
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(texts(in: nodes).contains("rich"),
                      "68_400.0 > 1000 must evaluate through the cross-file static let")
    }

    // MARK: - enum cases resolve as members

    func testEnumCaseResolvesAsMember() throws {
        let home = """
        struct Home: View {
            let mode = Mode.demo
            var body: some View {
                Text("m")
            }
        }
        """
        let (_, evaluator, _) = try renderHome(home, mode: true)
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "Mode.demo must not error, got: \(errors.map(\.message))")
    }

    // MARK: - genuinely unknown identifiers still error

    func testTrulyUnknownIdentifierStillErrors() throws {
        let home = """
        struct Home: View {
            var body: some View {
                Text(UnknownThing.value ? "y" : "n")
            }
        }
        """
        let (_, evaluator, _) = try renderHome(home)
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.contains { $0.key == .diagUnknownIdentifier },
                      "unknown types must still be errors")
    }

    // MARK: - didSet / initializers never execute

    func testSideEffectfulMembersNeverExecute() throws {
        // isEnabled's didSet writes UserDefaults — the probe must not run it.
        // If it did, this test would write to the real defaults; instead we
        // assert the sentinel key stays absent.
        UserDefaults.standard.removeObject(forKey: "demo")
        let home = """
        struct Home: View {
            var body: some View {
                Text(DemoMode.shared.isEnabled ? "demo" : "real")
            }
        }
        """
        _ = try renderHome(home)
        XCTAssertNil(UserDefaults.standard.object(forKey: "demo"),
                     "didSet must never execute during preview evaluation")
    }
}
