import XCTest
@testable import CodeBerry

/// 4.0.2 P0-1 / P0-2: unified index cap, incremental/background indexing,
/// and the Analyzer → Index → Evaluator resolution chain.
///
/// Regression context: in the real XiaoZhangGui project (233 Swift files)
/// the old 100-file preview-index cap left V35/V36 components unindexed, so
/// `HomeView` rendered them as `[?]` placeholders.
///
/// 4.0.2: @MainActor — the tests drive `rebuildInBackground`, which is
/// MainActor-isolated (it snapshots MainActor-isolated store state).
@MainActor
final class PreviewLargeProjectIndexTests: XCTestCase {

    /// Builds a temp project with `fileCount` tiny Swift files; the last one
    /// (`Target.swift`) defines `TargetCard`.
    private func makeProject(fileCount: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB402Index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<fileCount {
            let name = String(format: "File%03d.swift", i)
            let source = "struct Pad\(i): View { var body: some View { Text(\"p\(i)\") } }"
            try source.write(to: root.appendingPathComponent(name),
                             atomically: true, encoding: .utf8)
        }
        let target = """
        struct TargetCard: View {
            var body: some View { Text("from-target") }
        }
        """
        try target.write(to: root.appendingPathComponent("Target.swift"),
                         atomically: true, encoding: .utf8)
        return root
    }

    private func readFile(in root: URL) -> (String) -> String? {
        { path in
            let rel = path.hasPrefix("Proj/") ? String(path.dropFirst("Proj/".count)) : path
            return try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
        }
    }

    // MARK: - P0-1: unified cap

    func testUnifiedCapCoversFilesPastOld100Limit() throws {
        // 150 files: past the old 100-file cap, under the unified 1000 cap.
        let root = try makeProject(fileCount: 150)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = PreviewProjectIndex()
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: "Proj/Target.swift",
                     currentSource: "struct TargetCard: View { var body: some View { Text(\"x\") } }",
                     readFile: readFile(in: root))

        XCTAssertEqual(ProjectIndexPolicy.maxFiles, 1000)
        XCTAssertEqual(ProjectIndexPolicy.maxFiles, ProjectAnalyzer.maxFiles,
                       "analyzer and preview index must share one cap")
        XCTAssertNotNil(index.viewsByName["TargetCard"],
                        "files past the old 100-file cap must be indexed")
        XCTAssertNotNil(index.viewsByName["Pad149"])
    }

    // MARK: - P0-1: incremental (hash-gated)

    func testIncrementalUpdateKeepsUnchangedEntries() throws {
        let root = try makeProject(fileCount: 10)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = PreviewProjectIndex()
        let read = readFile(in: root)
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "", readFile: read)
        XCTAssertNotNil(index.viewsByName["Pad5"])

        // Delete a file on disk; the next update must drop its entry…
        try FileManager.default.removeItem(at: root.appendingPathComponent("File005.swift"))
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "", readFile: read)
        XCTAssertNil(index.viewsByName["Pad5"], "deleted files must leave the index")
        // …while untouched files keep their entries without re-parsing.
        XCTAssertNotNil(index.viewsByName["Pad6"])
        XCTAssertNotNil(index.viewsByName["TargetCard"])
    }

    // MARK: - P0-1: background rebuild

    func testBackgroundRebuildIndexesAllFiles() async throws {
        let root = try makeProject(fileCount: 60)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = PreviewProjectIndex()
        await index.rebuildInBackground(
            projectRoot: root, projectName: "Proj",
            currentPath: "Proj/Target.swift",
            currentSource: "struct TargetCard: View { var body: some View { Text(\"live\") } }",
            readFile: readFile(in: root))

        XCTAssertFalse(index.isIndexing)
        XCTAssertNotNil(index.viewsByName["TargetCard"])
        XCTAssertNotNil(index.viewsByName["Pad59"])
        // The live in-memory source wins over disk for the current file.
        let entry = try XCTUnwrap(index.viewsByName["TargetCard"])
        XCTAssertEqual(entry.file, "Proj/Target.swift")
    }

    // MARK: - P0-2: resolution order — index before unsupported

    /// A component past the old cap must render its real content, not `[?]`.
    func testCrossFileComponentPastOldCapRendersContent() async throws {
        let root = try makeProject(fileCount: 120)
        defer { try? FileManager.default.removeItem(at: root) }

        let homeSource = """
        struct Home: View {
            var body: some View {
                VStack { TargetCard() }
            }
        }
        """
        let index = PreviewProjectIndex()
        await index.rebuildInBackground(
            projectRoot: root, projectName: "Proj",
            currentPath: "Proj/Home.swift", currentSource: homeSource,
            readFile: readFile(in: root))

        let engine = PreviewEngine(source: homeSource)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        evaluator.projectIndex = index
        let nodes = try evaluator.renderRoot()

        var sawTarget = false, sawUnsupported = false
        func walk(_ nodes: [PreviewViewNode]) {
            for n in nodes {
                switch n.kind {
                case .text(let s): if s == "from-target" { sawTarget = true }
                case .unsupported: sawUnsupported = true
                case .stack(_, _, _, let children): walk(children)
                case .group(let children): walk(children)
                default: break
                }
            }
        }
        walk(nodes)
        XCTAssertTrue(sawTarget, "cross-file TargetCard must resolve through the index")
        XCTAssertFalse(sawUnsupported, "no [?] placeholder for an indexed component")
    }

    /// Current-file definition wins over the index (order step 1 > step 2).
    func testCurrentFileDefinitionWinsOverIndex() throws {
        let root = try makeProject(fileCount: 5)
        defer { try? FileManager.default.removeItem(at: root) }

        // Index has TargetCard rendering "from-target" (on disk)…
        let index = PreviewProjectIndex()
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "", readFile: readFile(in: root))

        // …but the current file redefines it locally.
        let homeSource = """
        struct TargetCard: View {
            var body: some View { Text("local-override") }
        }
        struct Home: View {
            var body: some View { TargetCard() }
        }
        """
        let engine = PreviewEngine(source: homeSource)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        evaluator.projectIndex = index
        // 4.0.3 S8 (P0-F): explicit target — the source declares two views
        // (TargetCard, Home); ambiguous selection must never be silent.
        let nodes = try evaluator.renderRoot(targetView: "Home")

        var texts: [String] = []
        func walk(_ nodes: [PreviewViewNode]) {
            for n in nodes {
                if case .text(let s) = n.kind { texts.append(s) }
                if case .stack(_, _, _, let c) = n.kind { walk(c) }
                if case .group(let c) = n.kind { walk(c) }
            }
        }
        walk(nodes)
        XCTAssertTrue(texts.contains("local-override"),
                      "current-file definition must win over the index")
        XCTAssertFalse(texts.contains("from-target"))
    }

    // MARK: - P1-11: mtime/size pre-filter (no read+hash for unchanged files)

    func testWarmPassSkipsUnchangedFilesWithoutReading() throws {
        let root = try makeProject(fileCount: 20)
        defer { try? FileManager.default.removeItem(at: root) }

        let index = PreviewProjectIndex()
        let base = readFile(in: root)
        var reads = 0
        let countingRead: (String) -> String? = { path in
            reads += 1
            return base(path)
        }
        // currentPath nil: every file goes through the background path.
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "",
                     readFile: countingRead)
        XCTAssertEqual(reads, 21, "cold pass reads every file")

        // Warm pass with no changes: mtime/size match → zero reads.
        reads = 0
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "",
                     readFile: countingRead)
        XCTAssertEqual(reads, 0,
                       "P1-11: warm pass must not re-read unchanged files")

        // Change exactly one file → only it is re-read and re-parsed.
        try "struct Pad0: View { var body: some View { Text(\"changed\") } }"
            .write(to: root.appendingPathComponent("File000.swift"),
                   atomically: true, encoding: .utf8)
        reads = 0
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: nil, currentSource: "",
                     readFile: countingRead)
        XCTAssertEqual(reads, 1, "only the changed file is re-read")
        XCTAssertNotNil(index.viewsByName["Pad0"])
    }
}
