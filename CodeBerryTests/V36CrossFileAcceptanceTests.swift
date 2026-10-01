import XCTest
@testable import CodeBerry

/// 4.0.3 S5: cross-file verification over the V36 acceptance corpus.
///
/// All 8 real views render through the full pipeline (S1 fixtures → S2
/// system registry → S3 computed properties → S4 resolver). None of the 6
/// red-line identifiers — DemoMode, greetingPrefix, V32, ownerDisplayName,
/// handlingItems, Calendar — is ever an unknown-identifier error.
final class V36CrossFileAcceptanceTests: XCTestCase {

    static let views = ["HomeView", "TodoView", "CalendarView", "PerformanceView",
                        "CustomerView", "ExpiryView", "MemoView", "ProfileView"]
    /// The 6 identifiers that 4.0.2 reported as unknown (audit §2).
    static let redLines = ["DemoMode", "greetingPrefix", "V32",
                           "ownerDisplayName", "handlingItems", "Calendar"]

    /// Every view renders nodes; no red-line identifier is `.error`.
    func testAllViewsRenderWithoutRedLineErrors() throws {
        let index = try V36Acceptance.makeIndex()
        var failures: [String] = []
        for view in Self.views {
            let (nodes, evaluator) = try V36Acceptance.evaluate(viewName: view, index: index)
            if nodes.isEmpty {
                failures.append("\(view): rendered no nodes")
            }
            let redErrors = evaluator.diagnostics.filter { d in
                d.severity == .error &&
                d.params.contains(where: Self.redLines.contains)
            }
            for e in redErrors {
                failures.append("\(view): [error] \(e.message)")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "cross-file acceptance failed:\n" + failures.joined(separator: "\n"))
    }

    /// The Calendar chain end-to-end: `Calendar.current`, `.component`,
    /// `.date(byAdding:)`, `.dateInterval`, `.range` — info/warning at most.
    func testCalendarChainHasNoErrors() throws {
        let index = try V36Acceptance.makeIndex()
        let (nodes, evaluator) = try V36Acceptance.evaluate(viewName: "CalendarView",
                                                            index: index)
        XCTAssertFalse(nodes.isEmpty, "CalendarView must render")
        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "Calendar chain must have no errors: \(errors.map(\.message))")
        // The chain is observable: approximations are recorded as info.
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagSystemApproximation
        }, "Calendar approximations must be recorded")
    }

    /// Per-view diagnostic census — feeds the S7 Before/After report.
    func testDiagnosticCensus() throws {
        let index = try V36Acceptance.makeIndex()
        var lines: [String] = []
        for view in Self.views {
            let (_, evaluator) = try V36Acceptance.evaluate(viewName: view, index: index)
            let counts = Dictionary(grouping: evaluator.diagnostics, by: \.severity)
                .mapValues(\.count)
            lines.append("\(view): error=\(counts[.error] ?? 0) " +
                         "warning=\(counts[.warning] ?? 0) " +
                         "info=\(counts[.info] ?? 0) " +
                         "needsMock=\(counts[.needsMock] ?? 0)")
        }
        // Visible in the CI test log for the release report.
        print("V36-CENSUS:\n" + lines.joined(separator: "\n"))
    }
}
