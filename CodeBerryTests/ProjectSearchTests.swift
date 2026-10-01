import XCTest
@testable import CodeBerry

/// M2: ProjectSearch — 项目全文搜索.
final class ProjectSearchTests: XCTestCase {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeberry-searchtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "struct HomeView: View {\n  var body: some View { Text(\"hello\") }\n}\n"
            .write(to: root.appendingPathComponent("HomeView.swift"), atomically: true, encoding: .utf8)
        try "struct SettingsView: View {\n  var body: some View { Text(\"world\") }\n}\n"
            .write(to: root.appendingPathComponent("SettingsView.swift"), atomically: true, encoding: .utf8)
        try "binary \0 content".write(to: root.appendingPathComponent("blob.bin"),
                                      atomically: true, encoding: .utf8)
        return root
    }

    func testFindsMatchesWithLineNumbers() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let hits = ProjectSearch.search(projectRoot: root, query: "body")
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.line == 2 })
        XCTAssertTrue(hits.allSatisfy { $0.lineText.contains("body") })
    }

    func testCaseInsensitiveByDefault() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let hits = ProjectSearch.search(projectRoot: root, query: "HOMEVIEW")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].filePath, "HomeView.swift")
    }

    func testCaseSensitive() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(ProjectSearch.search(projectRoot: root, query: "HOMEVIEW",
                                           caseSensitive: true).isEmpty)
    }

    func testSkipsBinaryFiles() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let hits = ProjectSearch.search(projectRoot: root, query: "binary")
        XCTAssertTrue(hits.isEmpty)
    }

    func testEmptyQueryReturnsNothing() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(ProjectSearch.search(projectRoot: root, query: "").isEmpty)
    }

    func testExtensionFilter() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let hits = ProjectSearch.search(projectRoot: root, query: "hello",
                                        fileExtension: "md")
        XCTAssertTrue(hits.isEmpty)
    }
}
