import XCTest
@testable import CodeBerry

/// 4.0.2 P0-7 E2E: fixture generation against the REAL XiaoZhangGui
/// `HomeView.swift` (read-only reference checkout).
///
/// The reference path can be overridden with `XZG_REFERENCE_HOME`; when the
/// checkout is absent (e.g. CI) the test skips loudly instead of failing —
/// the synthetic `PreviewFixtureSwiftDataTests` always run and cover the
/// generator logic itself.
final class XiaoZhangGuiHomePreviewFixtureTests: XCTestCase {

    private func realHomeViewSource() throws -> String {
        let path = ProcessInfo.processInfo.environment["XZG_REFERENCE_HOME"]
            ?? (NSHomeDirectory() + "/workspace/xzg-v361/XiaoZhangGui/Features/Home/HomeView.swift")
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("XiaoZhangGui reference checkout not available at \(path)")
        }
        return source
    }

    func testRealHomeViewGetsABypassingWrapper() throws {
        let source = try realHomeViewSource()
        let plan = try XCTUnwrap(
            PreviewFixtureGenerator.plan(for: "HomeView", in: source),
            "the real HomeView uses @Query → a wrapper is required")

        XCTAssertEqual(plan.wrapperName, "HomeViewPreviewFixture")
        // The real @Query properties, in declaration order.
        XCTAssertEqual(plan.modelTypes,
                       ["Todo", "Performance", "ExpiryItem", "CustomerRequest", "Memo"])
        XCTAssertTrue(plan.source.contains("inMemory: true"))
        XCTAssertTrue(plan.source.contains("HomeView()"))
        XCTAssertTrue(plan.source.contains("#Preview"))
        XCTAssertFalse(plan.source.contains("@Query"))
    }

    func testRealHomeViewWrapperHasNoLiveDatabaseOrNetwork() throws {
        let source = try realHomeViewSource()
        let plan = try XCTUnwrap(PreviewFixtureGenerator.plan(for: "HomeView", in: source))
        XCTAssertFalse(plan.source.contains("URLSession"))
        XCTAssertFalse(plan.source.contains("try ModelContainer"))
        XCTAssertFalse(plan.source.contains("ModelConfiguration("))
    }
}
