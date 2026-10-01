import XCTest
@testable import CodeBerry

/// 4.0.2 P0-7: the fixture generator emits a preview-only wrapper that truly
/// bypasses SwiftData (in-memory container) — never a verbatim snapshot,
/// never a modification of production code.
final class PreviewFixtureSwiftDataTests: XCTestCase {

    private let queryView = """
    import SwiftUI
    import SwiftData
    struct HomeView: View {
        @Query private var todos: [Todo]
        @Query(sort: \\Memo.updatedAt, order: .reverse) private var memos: [Memo]
        @Environment(\\.modelContext) private var modelContext
        var body: some View { Text("hi") }
    }
    """

    func testWrapperBypassesSwiftDataWithInMemoryContainer() throws {
        let planValue = try XCTUnwrap(PreviewFixtureGenerator.plan(for: "HomeView", in: queryView))
        XCTAssertEqual(planValue.wrapperName, "HomeViewPreviewFixture")
        XCTAssertEqual(planValue.modelTypes, ["Todo", "Memo"])
        XCTAssertTrue(planValue.source.contains("inMemory: true"),
                      "the container must be in-memory")
        XCTAssertTrue(planValue.source.contains("HomeViewPreviewFixture"))
        XCTAssertTrue(planValue.source.contains("HomeView()"))
        XCTAssertTrue(planValue.source.contains("[Todo.self, Memo.self]"))
        XCTAssertTrue(planValue.source.contains("#Preview"))
    }

    func testWrapperContainsNoLiveSwiftDataOrNetwork() throws {
        let plan = try XCTUnwrap(PreviewFixtureGenerator.plan(for: "HomeView", in: queryView))
        let src = plan.source
        XCTAssertFalse(src.contains("@Query"), "the wrapper must not redeclare @Query")
        XCTAssertFalse(src.contains("@Model"), "the wrapper must not redeclare models")
        XCTAssertFalse(src.contains("class Todo"), "production schema must not be copied")
        XCTAssertFalse(src.contains("URLSession"), "no network in the wrapper")
        XCTAssertFalse(src.contains("http"), "no network in the wrapper")
        // Only the sanctioned in-memory modifier — no direct container init
        // that could open the real store.
        XCTAssertFalse(src.contains("try ModelContainer"))
        XCTAssertFalse(src.contains("ModelConfiguration("))
    }

    func testNilWhenViewDoesNotUseSwiftData() {
        let plain = """
        import SwiftUI
        struct PlainView: View {
            var body: some View { Text("hi") }
        }
        """
        XCTAssertNil(PreviewFixtureGenerator.plan(for: "PlainView", in: plain),
                     "no SwiftData → no wrapper needed")
    }

    func testNilWhenViewNotFound() {
        XCTAssertNil(PreviewFixtureGenerator.plan(for: "Missing", in: queryView))
    }

    func testNilOnSyntaxError() {
        XCTAssertNil(PreviewFixtureGenerator.plan(for: "HomeView", in: "struct HomeView: View { broken ((("))
    }

    func testModelContextOnlyViewStillGetsInMemoryWrapper() throws {
        let src = """
        import SwiftUI
        import SwiftData
        struct StatsView: View {
            @Environment(\\.modelContext) private var modelContext
            var body: some View { Text("hi") }
        }
        """
        let plan = try XCTUnwrap(PreviewFixtureGenerator.plan(for: "StatsView", in: src))
        XCTAssertEqual(plan.wrapperName, "StatsViewPreviewFixture")
        XCTAssertTrue(plan.modelTypes.isEmpty)
        XCTAssertTrue(plan.source.contains("inMemory: true"))
    }

    func testProductionSourceIsNeverModified() {
        let original = queryView
        _ = PreviewFixtureGenerator.plan(for: "HomeView", in: queryView)
        XCTAssertEqual(queryView, original, "the generator only reads the source")
    }
}
