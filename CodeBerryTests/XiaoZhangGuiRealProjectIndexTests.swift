import XCTest
@testable import CodeBerry

/// 4.0.3 S1: the project index over the V36 acceptance tree.
///
/// The corpus is `PreviewFixtures/V36Acceptance/` — desensitized XiaoZhangGui
/// V3.6 fixtures (identifiers + type structure preserved, business logic
/// removed, per the approved 4.0.3 plan). Unlike 4.0.2's version of this
/// suite, these assertions run on CI: no checkout, no skip.
///
/// The real-tree counterpart is `XiaoZhangGuiRealV36AcceptanceTests`
/// (`XZG_REFERENCE_ROOT`, explicit failure when the checkout is absent).
final class XiaoZhangGuiRealProjectIndexTests: XCTestCase {

    /// The acceptance tree's views resolve cross-file (not `[?]`).
    func testAcceptanceTreeIndexResolvesHomeComponents() throws {
        let index = try V36Acceptance.makeIndex()

        XCTAssertGreaterThanOrEqual(
            index.totalCount, 10,
            "the acceptance corpus must be fully listed")
        XCTAssertEqual(index.indexedCount, index.totalCount)
        for name in ["HomeView", "HomeActionRow",
                     "TodoView", "CalendarView", "PerformanceView",
                     "CustomerView", "CustomerRow",
                     "ExpiryView", "ExpiryRow",
                     "MemoView", "MemoCard",
                     "ProfileView"] {
            XCTAssertNotNil(index.viewsByName[name],
                             "\(name) must resolve in the acceptance-tree index")
        }
    }

    /// `DemoMode` (a `final class`, not a View) resolves as an ordinary
    /// cross-file type instead of an unknown identifier.
    func testAcceptanceTreeIndexResolvesDemoModeType() throws {
        let index = try V36Acceptance.makeIndex()

        let demo = try XCTUnwrap(index.typesByName["DemoMode"],
                                 "DemoMode must resolve as a cross-file type")
        XCTAssertTrue(demo.isSingleton, "static let shared = DemoMode() is the singleton pattern")
        XCTAssertEqual(demo.instanceMembers["isEnabled"], "Bool")
        XCTAssertEqual(demo.instanceMembers["sessionID"], "UUID")
    }

    /// `V32` resolves as an enum: `static let`s with literal values are
    /// known values, `@MainActor` computed statics stay opaque (never
    /// executed, approximated at render time).
    func testAcceptanceTreeIndexResolvesV32() throws {
        let index = try V36Acceptance.makeIndex()

        let v32 = try XCTUnwrap(index.typesByName["V32"],
                                "V32 must resolve as a cross-file enum")
        XCTAssertEqual(v32.kind, .enum)
        XCTAssertNotNil(v32.staticValues["hero"], "static let hero = Color(...) must have a value")
        XCTAssertTrue(v32.opaqueStatics.contains("pageBG"),
                      "@MainActor static var pageBG must be opaque, never executed")
    }

    /// 4.0.3 S1 observability: a same-name symbol defined in two files is a
    /// recorded warning — never a silent last-writer-wins.
    func testSameNameSymbolConflictEmitsWarning() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("V36Conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "import SwiftUI\nstruct DupView: View { var body: some View { Text(\"a\") } }"
            .write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "import SwiftUI\nstruct DupView: View { var body: some View { Text(\"b\") } }"
            .write(to: dir.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)

        let index = PreviewProjectIndex()
        index.update(projectRoot: dir, projectName: "Dup",
                     currentPath: nil, currentSource: "",
                     readFile: { path in
                         let rel = String(path.dropFirst("Dup/".count))
                         return try? String(contentsOf: dir.appendingPathComponent(rel),
                                             encoding: .utf8)
                     })

        let conflicts = index.indexDiagnostics.filter { $0.key == .diagIndexSymbolConflict }
        XCTAssertEqual(conflicts.count, 1, "exactly one conflict must be recorded")
        XCTAssertTrue(conflicts.allSatisfy { $0.severity == .warning })
        XCTAssertNotNil(index.viewsByName["DupView"], "the symbol still resolves (last file wins)")
    }

    /// A clean corpus records no index diagnostics.
    func testAcceptanceTreeHasNoIndexConflicts() throws {
        let index = try V36Acceptance.makeIndex()
        XCTAssertTrue(index.indexDiagnostics.isEmpty,
                      "the acceptance corpus must be conflict-free: \(index.indexDiagnostics.map(\.message))")
    }
}
