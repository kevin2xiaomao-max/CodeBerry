import XCTest
@testable import CodeBerry

/// 4.0.3 S12 (P0-J): single fixture pipeline parity.
///
/// Every fixture entry point goes through
/// `pipelinePlan → validate → generate → register`. These tests lock that
/// the two UI entries (canvas action, candidates sheet) produce the same
/// fixture for the same view, and that the old `header + source` fallback
/// is gone.
final class FixturePipelineParityTests: XCTestCase {

    private let homeView = """
        import SwiftUI
        import SwiftData
        struct HomeView: View {
            @Query var todos: [Todo]
            var body: some View { Text("home") }
        }
        """

    private let plainView = """
        import SwiftUI
        struct PlainView: View {
            var body: some View { Text("plain") }
        }
        """

    /// Both UI entries resolve the same plan for the same view+source.
    func testEntriesAgreeOnPlan() throws {
        // Entry 1 (canvas action): pipelinePlan(for: selectedViewName, in: source)
        let viaCanvas = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "HomeView", in: homeView))
        // Entry 2 (candidates sheet): pipelinePlan(for: c.viewName, in: src)
        let viaSheet = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "HomeView", in: homeView))
        XCTAssertEqual(viaCanvas.wrapperName, viaSheet.wrapperName)
        XCTAssertEqual(viaCanvas.fileName, viaSheet.fileName)
        XCTAssertTrue(PreviewFixtureGenerator.validate(viaCanvas, source: homeView))
        XCTAssertTrue(PreviewFixtureGenerator.validate(viaSheet, source: homeView))
        XCTAssertEqual(PreviewFixtureGenerator.generate(viaCanvas, from: homeView),
                       PreviewFixtureGenerator.generate(viaSheet, from: homeView),
                       "both entries must generate byte-identical fixtures")
    }

    /// A SwiftData view gets the in-memory wrapper through the pipeline.
    func testSwiftDataViewGetsWrapper() throws {
        let plan = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "HomeView", in: homeView))
        guard case .swiftDataWrapper(let models) = plan.kind else {
            return XCTFail("expected swiftDataWrapper, got \(plan.kind)")
        }
        XCTAssertEqual(models, ["Todo"])
        XCTAssertEqual(plan.wrapperName, "HomeViewPreviewFixture")
        let src = PreviewFixtureGenerator.generate(plan, from: homeView)
        XCTAssertTrue(src.contains("inMemory: true"))
        XCTAssertTrue(src.contains("struct HomeViewPreviewFixture: View"))
    }

    /// A non-SwiftData view gets an EXPLICIT snapshot plan — never nil,
    /// never the old ad-hoc header+source branch.
    func testPlainViewGetsExplicitSnapshot() throws {
        let plan = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "PlainView", in: plainView))
        guard case .snapshot = plan.kind else {
            return XCTFail("expected snapshot, got \(plan.kind)")
        }
        XCTAssertEqual(plan.wrapperName, "PlainViewFixture")
        XCTAssertTrue(PreviewFixtureGenerator.validate(plan, source: plainView))
        let src = PreviewFixtureGenerator.generate(plan, from: plainView)
        XCTAssertTrue(src.contains("single pipeline"), "must carry the new pipeline header")
        XCTAssertFalse(src.contains("CodeBerry 4.0 (M3)"), "the old M3 header path is deleted")
        XCTAssertTrue(src.contains("struct PlainView: View"))
    }

    /// Missing view / broken source → nil (no fixture from nothing).
    func testNilWhenViewMissingOrBroken() {
        XCTAssertNil(PreviewFixtureGenerator.pipelinePlan(for: "Missing", in: homeView))
        XCTAssertNil(PreviewFixtureGenerator.pipelinePlan(
            for: "HomeView", in: "struct HomeView: View { broken ((("))
    }

    /// Register writes to PreviewFixtures/<wrapper>.swift and bumps the
    /// fixture revision (cache fingerprint dimension).
    func testRegisterWritesAndBumpsRevision() throws {
        let plan = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "HomeView", in: homeView))
        let registry = PreviewFixtureRegistry()
        var written: [(String, String)] = []
        let path = PreviewFixtureGenerator.register(
            plan, source: homeView, project: "Proj", registry: registry) { p, c in
                written.append((p, c)); return true
            }
        XCTAssertEqual(path, "Proj/PreviewFixtures/HomeViewPreviewFixture.swift")
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].0, path)
        XCTAssertEqual(registry.revision, 1)
        XCTAssertEqual(registry.source(for: "HomeViewPreviewFixture"), written[0].1)
    }

    /// A failed write registers nothing.
    func testFailedWriteRegistersNothing() throws {
        let plan = try XCTUnwrap(PreviewFixtureGenerator.pipelinePlan(for: "PlainView", in: plainView))
        let registry = PreviewFixtureRegistry()
        let path = PreviewFixtureGenerator.register(
            plan, source: plainView, project: "Proj", registry: registry) { _, _ in false }
        XCTAssertNil(path)
        XCTAssertEqual(registry.revision, 0)
    }
}
