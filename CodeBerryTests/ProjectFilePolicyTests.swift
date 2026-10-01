import XCTest
@testable import CodeBerry

/// 4.0.3 S11 (P0-I): the Analyzer, the ProjectIndex, and Page Discovery
/// share one `PreviewProjectFilePolicy` — they must agree on the file set.
final class ProjectFilePolicyTests: XCTestCase {

    /// Build a tree with excluded dirs, a fixture, and a production file.
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB403Policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let view = "import SwiftUI\nstruct HomeView: View { var body: some View { Text(\"x\") } }\n"
        let junk = "struct Junk {}\n"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App"),
                                                withIntermediateDirectories: true)
        try view.write(to: root.appendingPathComponent("App/HomeView.swift"),
                       atomically: true, encoding: .utf8)
        for dir in ["Pods", "node_modules", "DerivedData", "fastlane"] {
            let d = root.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try junk.write(to: d.appendingPathComponent("Junk.swift"),
                           atomically: true, encoding: .utf8)
        }
        let fixtures = root.appendingPathComponent("PreviewFixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        try junk.write(to: fixtures.appendingPathComponent("F.swift"),
                       atomically: true, encoding: .utf8)
        return root
    }

    private func readFile(root: URL) -> (String) -> String? {
        { path in
            let rel = path.hasPrefix("Proj/") ? String(path.dropFirst("Proj/".count)) : path
            return try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
        }
    }

    /// All three agree: excluded dirs are out everywhere.
    func testThreePlacesAgree() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // 1. The policy itself.
        let listed = PreviewProjectFilePolicy.default.swiftFiles(under: root).files
        let rels = listed.map(\.rel)
        XCTAssertTrue(rels.contains("App/HomeView.swift"), "\(rels)")
        XCTAssertFalse(rels.contains(where: { $0.hasPrefix("Pods/") }), "\(rels)")
        XCTAssertFalse(rels.contains(where: { $0.hasPrefix("node_modules/") }), "\(rels)")

        // 2. The Analyzer (Page Discovery).
        let analysis = ProjectAnalyzer.analyze(root: root)
        XCTAssertTrue(analysis.candidates.map(\.viewName).contains("HomeView"))
        XCTAssertFalse(analysis.candidates.contains(where: { $0.filePath.hasPrefix("Pods/") }))

        // 3. The ProjectIndex.
        let index = PreviewProjectIndex()
        index.update(projectRoot: root, projectName: "Proj",
                     currentPath: "Proj/App/HomeView.swift",
                     currentSource: try String(contentsOf: root.appendingPathComponent("App/HomeView.swift"),
                                               encoding: .utf8),
                     readFile: readFile(root: root))
        // App/HomeView.swift + PreviewFixtures/F.swift; Pods etc. excluded.
        XCTAssertEqual(index.indexedCount, 2, "indexed \(index.indexedCount), expected 2")
        XCTAssertNil(index.viewsByName["Junk"])
        XCTAssertNotNil(index.viewsByName["HomeView"])
    }

    /// Every excluded dir name is honored.
    func testExcludedDirs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CB403Excl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in [".git", ".build", "Pods", "DerivedData", ".swiftpm",
                    "Carthage", "node_modules", "fastlane"] {
            let d = root.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try "struct Junk {}\n".write(to: d.appendingPathComponent("Junk.swift"),
                                         atomically: true, encoding: .utf8)
        }
        let rels = PreviewProjectFilePolicy.default.swiftFiles(under: root).files.map(\.rel)
        XCTAssertTrue(rels.isEmpty, "excluded dirs leaked: \(rels)")
    }

    /// Source roots narrow the file set.
    func testSourceRoots() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = PreviewProjectFilePolicy(sourceRoots: ["App"])
        let rels = policy.swiftFiles(under: root).files.map(\.rel)
        XCTAssertEqual(rels, ["App/HomeView.swift"], "\(rels)")
    }
}
