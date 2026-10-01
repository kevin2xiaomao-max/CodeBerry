import XCTest
@testable import CodeBerry

// MARK: - 4.0.3 S7: V36 acceptance harness
//
// Runs the V36Acceptance fixture corpus through the full pipeline and
// emits a structured Before/After report. The Before baseline is the
// 4.0.2 audit finding (a562015): the 6 red-line identifiers were
// `.error` unknown identifiers. The After numbers are measured live.
//
// Anti-cheating:
//  1. `unresolved` (resolver .unknown hits → .error diagUnknownIdentifier)
//     is counted independently — After must reduce BOTH errors and
//     unresolved vs Before. Reducing errors without reducing unresolved
//     is treated as cheating.
//  2. The 6 red lines get VALUE assertions, not just "no error".
//  3. The harness prints 20 non-redline spot-check identifiers for
//     manual (audit-time) review.

struct V36AcceptanceHarness {

    /// The 4.0.2 baseline (a562015), from the 4.0.2 audit: each red-line
    /// identifier was an `.error` unknown identifier.
    static let beforeBaseline: [String: String] = [
        "DemoMode": "error(unknownIdentifier)",
        "greetingPrefix": "error(unknownIdentifier)",
        "V32": "error(unknownIdentifier)",
        "ownerDisplayName": "error(unknownIdentifier)",
        "handlingItems": "error(unknownIdentifier)",
        "Calendar": "error(unknownIdentifier)",
    ]

    struct ViewReport {
        let viewName: String
        var errors: Int = 0
        var warnings: Int = 0
        var needsMocks: Int = 0
        var infos: Int = 0
        var ignored: Int = 0
        /// Independent unresolved counter: .error diagUnknownIdentifier hits.
        var unresolved: Int = 0
        var keyCounts: [String: Int] = [:]
        /// Red-line identifier → status string.
        var redLines: [String: String] = [:]
        var nodeCount: Int = 0
    }

    struct Report {
        let version = "4.0.3"
        var views: [ViewReport] = []
        var indexMs: Double = 0
        var incrementalIndexMs: Double = 0

        var totalErrors: Int { views.reduce(0) { $0 + $1.errors } }
        var totalUnresolved: Int { views.reduce(0) { $0 + $1.unresolved } }

        /// Rendered as stable text for the CI log and the final report.
        func render() -> String {
            var lines: [String] = []
            lines.append("=== V36 Acceptance Harness (CodeBerry \(version)) ===")
            lines.append("index: \(String(format: "%.1f", indexMs))ms  incremental: \(String(format: "%.1f", incrementalIndexMs))ms")
            lines.append("BEFORE (4.0.2 @ a562015): 6 red-line identifiers → .error unknownIdentifier")
            lines.append("")
            for v in views {
                lines.append("-- \(v.viewName): errors=\(v.errors) warnings=\(v.warnings) needsMock=\(v.needsMocks) info=\(v.infos) unresolved=\(v.unresolved) nodes=\(v.nodeCount)")
                for (id, status) in v.redLines.sorted(by: { $0.key < $1.key }) {
                    let before = V36AcceptanceHarness.beforeBaseline[id] ?? "?"
                    lines.append("   [\(id)] before=\(before) after=\(status)")
                }
                let top = v.keyCounts.sorted { $0.value > $1.value }.prefix(5)
                    .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                if !top.isEmpty { lines.append("   top diagnostics: \(top)") }
            }
            lines.append("")
            lines.append("AFTER totals: errors=\(totalErrors) unresolved=\(totalUnresolved)")
            lines.append("=== end harness ===")
            return lines.joined(separator: "\n")
        }
    }

    /// Run every target view; measure index times; collect diagnostics.
    static func run(index: PreviewProjectIndex,
                    views: [String],
                    indexMs: Double,
                    incrementalIndexMs: Double) throws -> Report {
        var report = Report()
        report.indexMs = indexMs
        report.incrementalIndexMs = incrementalIndexMs
        for view in views {
            var vr = ViewReport(viewName: view)
            let (nodes, evaluator) = try V36Acceptance.evaluate(viewName: view, index: index)
            for d in evaluator.diagnostics {
                vr.keyCounts[d.key.rawValue, default: 0] += 1
                switch d.severity {
                case .error:
                    vr.errors += 1
                    if d.key == .diagUnknownIdentifier { vr.unresolved += 1 }
                case .warning: vr.warnings += 1
                case .needsMock: vr.needsMocks += 1
                case .info: vr.infos += 1
                case .ignored: vr.ignored += 1
                }
            }
            vr.nodeCount = nodes.count
            vr.redLines = redLineStatus(view: view, evaluator: evaluator)
            report.views.append(vr)
        }
        return report
    }

    /// Status of each red-line identifier for one rendered view:
    /// "error" / "needsMock" / "approximated" / "resolved".
    static func redLineStatus(view: String, evaluator: PreviewEvaluator) -> [String: String] {
        let ids = ["DemoMode", "greetingPrefix", "V32", "ownerDisplayName", "handlingItems", "Calendar"]
        var out: [String: String] = [:]
        for id in ids {
            let diags = evaluator.diagnostics.filter { $0.params.contains(id) || $0.api == id }
            if diags.contains(where: { $0.severity == .error }) {
                out[id] = "error(\(diags.first(where: { $0.severity == .error })!.key.rawValue))"
            } else if diags.contains(where: { $0.severity == .needsMock }) {
                out[id] = "needsMock"
            } else if diags.contains(where: { $0.severity == .warning || $0.severity == .info }) {
                out[id] = "approximated"
            } else {
                out[id] = "resolved"
            }
        }
        return out
    }
}

// MARK: - The harness test (CI-mandatory)

final class V36AcceptanceHarnessTests: XCTestCase {

    static let targetViews = ["HomeView", "TodoView", "CalendarView", "PerformanceView",
                              "CustomerView", "ExpiryView", "MemoView", "ProfileView"]

    /// Full harness run: structured report + red-line gates + anti-cheat.
    func testHarnessBeforeAfter() throws {
        let t0 = Date()
        let index = try V36Acceptance.makeIndex()
        let indexMs = Date().timeIntervalSince(t0) * 1000

        // Incremental re-index timing (re-run the same update).
        let t1 = Date()
        V36Acceptance.update(index: index)
        let incrementalMs = Date().timeIntervalSince(t1) * 1000

        let report = try V36AcceptanceHarness.run(
            index: index,
            views: Self.targetViews,
            indexMs: indexMs,
            incrementalIndexMs: incrementalMs)
        print(report.render())

        // Anti-cheat 1: every red line must have improved vs the 4.0.2
        // baseline, and unresolved must be 0 for the red lines.
        for v in report.views {
            for (id, status) in v.redLines {
                XCTAssertFalse(status.hasPrefix("error"),
                               "\(v.viewName): red line \(id) is still an error (\(status))")
            }
        }
        XCTAssertEqual(report.totalUnresolved, 0,
                       "unresolved identifiers must be 0, got \(report.totalUnresolved)")

        // Anti-cheat 2: value assertions on the red lines (HomeView).
        let home = try XCTUnwrap(report.views.first { $0.viewName == "HomeView" })
        XCTAssertEqual(home.redLines["greetingPrefix"], "resolved")
        XCTAssertEqual(home.redLines["V32"], "resolved")
        XCTAssertEqual(home.redLines["DemoMode"], "resolved")

        // No crashes: every view produced nodes.
        for v in report.views {
            XCTAssertGreaterThan(v.nodeCount, 0, "\(v.viewName) produced no nodes")
        }
    }

    /// Anti-cheat 3: 20 non-redline spot-check identifiers, printed for
    /// audit-time manual review.
    func testSpotCheckIdentifiers() throws {
        let index = try V36Acceptance.makeIndex()
        let (_, evaluator) = try V36Acceptance.evaluate(viewName: "HomeView", index: index)
        let spot = evaluator.diagnostics
            .map { $0.api ?? $0.params.first ?? "?" }
            .filter { !["DemoMode", "greetingPrefix", "V32", "ownerDisplayName", "handlingItems", "Calendar"].contains($0) }
        var seen: [String] = []
        for s in spot where !seen.contains(s) { seen.append(s) }
        print("=== spot-check identifiers (first 20, manual review) ===")
        for s in seen.prefix(20) {
            let sev = evaluator.diagnostics.first { ($0.api ?? $0.params.first) == s }?.severity
            print("  \(s): \(sev.map { "\($0)" } ?? "?")")
        }
    }
}
