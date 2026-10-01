import XCTest
@testable import CodeBerry

/// 4.0.2 P1-9: diagnostic severity discipline.
///
/// - Error: syntax / genuinely-unresolved identifiers / evaluator fatals only.
/// - Warning: SwiftData-unavailable / external packages / approximates.
/// - Info / NeedsMock: fixture requirements.
final class PreviewDiagnosticsSeverityTests: XCTestCase {

    private func evaluate(_ source: String) throws -> PreviewEvaluator {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        _ = try evaluator.renderRoot()
        return evaluator
    }

    func testMockNeededIsNeedsMockNotError() throws {
        let evaluator = try evaluate("""
        import SwiftUI
        struct Home: View {
            @StateObject var vm: HomeViewModel
            var body: some View { Text("hi") }
        }
        """)
        let diags = evaluator.diagnostics.filter { $0.key == .diagMockNeeded }
        XCTAssertFalse(diags.isEmpty, "an unfilled requirement must still be reported")
        XCTAssertTrue(diags.allSatisfy { $0.severity == .needsMock },
                      "fixture needs are NeedsMock, never Error")
        XCTAssertTrue(diags.allSatisfy { !$0.severity.blocksPreview },
                      "fixture needs must not block the preview")
    }

    func testUnknownIdentifierIsStillError() throws {
        let evaluator = try evaluate("""
        import SwiftUI
        struct Home: View {
            var body: some View { Text(totallyUnknownThing) }
        }
        """)
        let diags = evaluator.diagnostics.filter { $0.key == .diagUnknownIdentifier }
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.allSatisfy { $0.severity == .error })
        XCTAssertTrue(diags.allSatisfy { $0.severity.blocksPreview })
    }

    func testExternalPackageIsWarning() throws {
        let evaluator = try evaluate("""
        import SwiftUI
        import Charts
        struct Home: View {
            var body: some View { Chart { BarMark(x: .value("a", "b"), y: .value("c", 1)) } }
        }
        """)
        let diags = evaluator.diagnostics.filter { $0.key == .diagExternalPackageNotExecuted }
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.allSatisfy { $0.severity == .warning })
    }

    func testTypePreviewDefaultIsInfo() throws {
        let evaluator = try evaluate("""
        import SwiftUI
        struct DemoMode {
            static let shared = DemoMode()
            var isEnabled: Bool = false
        }
        struct Home: View {
            var body: some View { Text(DemoMode.shared.isEnabled ? "a" : "b") }
        }
        """)
        let diags = evaluator.diagnostics.filter { $0.key == .diagTypePreviewDefault }
        XCTAssertFalse(diags.isEmpty, "the opaque member fallback must be reported")
        XCTAssertTrue(diags.allSatisfy { $0.severity == .info })
    }
}
