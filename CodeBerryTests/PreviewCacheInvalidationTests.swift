import XCTest
@testable import CodeBerry

/// 4.0.3 S9 (P0-G): cache invalidation — 6-dimensional fingerprint.
///
/// A cache hit requires ALL dimensions to match:
/// source revision / targetViewName / ProjectIndex generation /
/// Mock+Profile revision / Runtime state revision / Fixture revision.
/// Each test below changes exactly one dimension and proves the next
/// evaluate is a MISS (re-evaluated) — stale previews are never served.
final class PreviewCacheInvalidationTests: XCTestCase {

    private func evaluate(source: String,
                          fileName: String = "Main.swift",
                          index: PreviewProjectIndex? = nil,
                          cache: inout IncrementalPreview.Cache,
                          runtime: PreviewRuntime = PreviewRuntime(),
                          mockStore: PreviewMockStore? = nil,
                          targetView: String? = nil,
                          fixtureRevision: Int = 0)
    -> (nodes: [PreviewViewNode], stats: IncrementalPreview.Stats) {
        let result = IncrementalPreview.evaluate(
            source: source, fileName: fileName, cache: &cache,
            runtime: runtime, projectIndex: index, mockStore: mockStore,
            targetView: targetView, fixtureRevision: fixtureRevision)
        return (result.nodes, result.stats)
    }

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

    // MARK: - 1. Dependency file change

    /// Changing a cross-file dependency re-indexes (generation bumps) and
    /// the next evaluate re-renders with the new value.
    func testDependencyFileChangeInvalidates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB403Cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mainSource = """
            import SwiftUI
            struct Main: View {
                var body: some View { Text(Dep.label) }
            }
            """
        try mainSource.write(to: root.appendingPathComponent("Main.swift"),
                             atomically: true, encoding: .utf8)
        // NOTE: different byte length than v2, so the mtime/size
        // pre-filter can't miss the change.
        try "struct Dep { static let label = \"version-one\" }".write(
            to: root.appendingPathComponent("Dep.swift"), atomically: true, encoding: .utf8)

        let index = PreviewProjectIndex()
        let updateIndex: () -> Void = {
            index.update(projectRoot: root, projectName: "Proj",
                         currentPath: "Proj/Main.swift", currentSource: mainSource,
                         readFile: { path in
                            let rel = path.hasPrefix("Proj/")
                                ? String(path.dropFirst("Proj/".count)) : path
                            return try? String(contentsOf: root.appendingPathComponent(rel),
                                                encoding: .utf8)
                         })
        }
        updateIndex()
        XCTAssertEqual(index.generation, 1)

        var cache = IncrementalPreview.Cache()
        var (nodes, stats) = evaluate(source: mainSource, index: index, cache: &cache,
                                      targetView: "Main")
        XCTAssertTrue(texts(in: nodes).contains("version-one"), "\(texts(in: nodes))")
        XCTAssertEqual(stats.misses, 1)

        // Unchanged re-evaluate: hit.
        (_, stats) = evaluate(source: mainSource, index: index, cache: &cache,
                              targetView: "Main")
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)

        // Change the dependency → generation bumps → next evaluate misses
        // and renders the new value.
        try "struct Dep { static let label = \"version-two!!\" }".write(
            to: root.appendingPathComponent("Dep.swift"), atomically: true, encoding: .utf8)
        updateIndex()
        XCTAssertEqual(index.generation, 2)

        (nodes, stats) = evaluate(source: mainSource, index: index, cache: &cache,
                                  targetView: "Main")
        XCTAssertEqual(stats.misses, 2, "dependency change must force re-evaluation")
        XCTAssertTrue(texts(in: nodes).contains("version-two!!"), "\(texts(in: nodes))")
    }

    // MARK: - 2. Mock value change

    /// Changing a mock value bumps the mock revision → re-evaluate.
    func testMockValueChangeInvalidates() {
        let source = """
            import SwiftUI
            struct M: View {
                var body: some View { Text("static") }
            }
            """
        let store = PreviewMockStore()
        var cache = IncrementalPreview.Cache()
        var stats: IncrementalPreview.Stats

        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        XCTAssertEqual(stats.misses, 1)
        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        XCTAssertEqual(stats.hits, 1)

        store.setValue(.string("x"), for: "something")
        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        XCTAssertEqual(stats.misses, 2, "mock change must force re-evaluation")
    }

    // MARK: - 3. Mock profile switch

    /// Switching the active MockCenter profile re-applies values
    /// (revision bumps) → re-evaluate.
    func testMockProfileSwitchInvalidates() {
        let source = """
            import SwiftUI
            struct M: View {
                var body: some View { Text("static") }
            }
            """
        let center = MockCenter(profiles: [
            MockProfile(displayName: "A", values: ["k": .string("a")]),
            MockProfile(displayName: "B", values: ["k": .string("b")]),
        ])
        let store = PreviewMockStore()
        center.activeProfileID = center.profiles[0].id
        center.apply(to: store)

        var cache = IncrementalPreview.Cache()
        var stats: IncrementalPreview.Stats
        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        XCTAssertEqual(stats.hits, 1)

        center.activeProfileID = center.profiles[1].id
        center.apply(to: store)
        (_, stats) = evaluate(source: source, cache: &cache, mockStore: store,
                              targetView: "M")
        XCTAssertEqual(stats.misses, 2, "profile switch must force re-evaluation")
    }

    // MARK: - 4. Runtime state change

    /// @State changes bump the runtime version → re-evaluate.
    func testRuntimeStateChangeInvalidates() {
        let source = """
            import SwiftUI
            struct C: View {
                @State var n = 0
                var body: some View { Text("n") }
            }
            """
        let runtime = PreviewRuntime()
        var cache = IncrementalPreview.Cache()
        var stats: IncrementalPreview.Stats

        (_, stats) = evaluate(source: source, cache: &cache, runtime: runtime,
                              targetView: "C")
        XCTAssertEqual(stats.misses, 1)
        (_, stats) = evaluate(source: source, cache: &cache, runtime: runtime,
                              targetView: "C")
        XCTAssertEqual(stats.hits, 1)

        runtime.set("C.n", .number(1))
        (_, stats) = evaluate(source: source, cache: &cache, runtime: runtime,
                              targetView: "C")
        XCTAssertEqual(stats.misses, 2, "runtime state change must force re-evaluation")
    }

    // MARK: - 5. Fixture change

    /// A fixture (re)generation bumps the fixture revision → re-evaluate.
    func testFixtureChangeInvalidates() {
        let source = """
            import SwiftUI
            struct F: View {
                var body: some View { Text("static") }
            }
            """
        let registry = PreviewFixtureRegistry()
        var cache = IncrementalPreview.Cache()
        var stats: IncrementalPreview.Stats

        (_, stats) = evaluate(source: source, cache: &cache, targetView: "F",
                              fixtureRevision: registry.revision)
        XCTAssertEqual(stats.misses, 1)
        (_, stats) = evaluate(source: source, cache: &cache, targetView: "F",
                              fixtureRevision: registry.revision)
        XCTAssertEqual(stats.hits, 1)

        registry.register(name: "FFixture", source: "// fixture")
        (_, stats) = evaluate(source: source, cache: &cache, targetView: "F",
                              fixtureRevision: registry.revision)
        XCTAssertEqual(stats.misses, 2, "fixture change must force re-evaluation")
    }
}
