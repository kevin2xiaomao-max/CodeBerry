import XCTest
@testable import CodeBerry

/// 4.0.3 S1: shared helpers for the V36 acceptance suites.
///
/// The acceptance corpus lives at repo-root `PreviewFixtures/V36Acceptance/`
/// (desensitized XiaoZhangGui V3.6 fixtures: identifiers + type structure
/// preserved, business logic removed). The path is resolved from this file's
/// compile-time location so the suites run on CI and locally.
enum V36Acceptance {
    static func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // CodeBerryTests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("PreviewFixtures/V36Acceptance", isDirectory: true)
    }

    static func fixtureSource(named name: String) throws -> String {
        try String(contentsOf: fixtureRoot().appendingPathComponent(name), encoding: .utf8)
    }

    /// Build a project index over the whole fixture tree (synchronous warm
    /// path — the corpus is small, no background pass needed).
    static func makeIndex(projectName: String = "V36Acceptance") throws -> PreviewProjectIndex {
        let root = fixtureRoot()
        let index = PreviewProjectIndex()
        let prefix = projectName + "/"
        index.update(
            projectRoot: root,
            projectName: projectName,
            currentPath: nil,
            currentSource: "",
            readFile: { path in
                let rel = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
                return try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            })
        return index
    }

    /// Evaluate one view file from the corpus with the project index attached.
    static func evaluate(viewName: String, index: PreviewProjectIndex) throws
        -> (nodes: [PreviewViewNode], evaluator: PreviewEvaluator)
    {
        let source = try fixtureSource(named: "\(viewName).swift")
        var cache = IncrementalPreview.Cache()
        let result = IncrementalPreview.evaluate(
            source: source,
            fileName: "\(viewName).swift",
            cache: &cache,
            runtime: PreviewRuntime(),
            projectIndex: index,
            mockStore: nil)
        return (result.nodes, result.evaluator)
    }
}
