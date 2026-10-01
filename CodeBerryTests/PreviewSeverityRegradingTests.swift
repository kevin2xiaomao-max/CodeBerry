import XCTest
@testable import CodeBerry

/// 4.0.3 S6 (P0-E): severity regrading.
///
/// - Reading a mock-requirement property (`@Query`, `@Environment`,
///   `@StateObject`, …) is NeedsMock, never an unknown-identifier error.
/// - SwiftData substitution policy (user decision): safe substitutions
///   (@Query → [], modelContext → stub) become NeedsMock; without a safe
///   substitution it stays an error.
/// - Genuinely unknown identifiers are still errors.
final class PreviewSeverityRegradingTests: XCTestCase {

    private func evaluate(_ source: String) throws -> PreviewEvaluator {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.fileName = "RegradeView.swift"
        evaluator.converter = parsed.converter
        _ = try evaluator.renderRoot()
        return evaluator
    }

    private func texts(in nodes: [PreviewViewNode]) -> [String] {
        var out: [String] = []
        for node in nodes {
            if case .text(let t) = node.kind { out.append(t) }
            switch node.kind {
            case .stack(_, _, _, let c), .list(let c), .group(let c): out += texts(in: c)
            case .button(let label, _): out += texts(in: label)
            default: break
            }
        }
        return out
    }

    /// A `@StateObject` read is NeedsMock + preview default — not an error.
    func testStateObjectReadIsNeedsMock() throws {
        let evaluator = try evaluate("""
            import SwiftUI
            struct V: View {
                @StateObject var vm: HomeViewModel
                var body: some View { Text("hi \\(vm)") }
            }
            """)
        // The requirement itself is reported…
        XCTAssertTrue(evaluator.diagnostics.contains { $0.key == .diagMockNeeded })
        // …but never as an error.
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "\(evaluator.diagnostics.map(\.message))")
    }

    /// A `@Query` read substitutes `[]` — NeedsMock, never an error.
    func testQueryReadSubstitutesEmptyArray() throws {
        let evaluator = try evaluate("""
            import SwiftUI
            struct V: View {
                @Query var todos: [Todo]
                var body: some View { Text("n\\(todos.count)") }
            }
            """)
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagSwiftDataSubstituted && $0.params.first == "todos"
        }, "got: \(evaluator.diagnostics.map(\.message))")
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "\(evaluator.diagnostics.map(\.message))")
    }

    /// `modelContext` substitutes a stub — NeedsMock, never an error.
    func testModelContextReadSubstitutesStub() throws {
        let evaluator = try evaluate("""
            import SwiftUI
            struct V: View {
                @Environment(\\.modelContext) var modelContext: ModelContext
                var body: some View {
                    let ctx = modelContext
                    Text("hi")
                }
            }
            """)
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagSwiftDataSubstituted && $0.params.first == "modelContext"
        }, "got: \(evaluator.diagnostics.map(\.message))")
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error })
    }

    /// An `@Environment` of a known project type stubs to its member types.
    func testEnvironmentKnownTypeStubs() throws {
        let evaluator = try evaluate("""
            import SwiftUI
            final class AppSettings {
                var ownerName: String = ""
            }
            struct V: View {
                @Environment(AppSettings.self) var settings: AppSettings
                var body: some View { Text(settings.ownerName) }
            }
            """)
        XCTAssertTrue(evaluator.diagnostics.contains { $0.key == .diagMockNeeded })
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "\(evaluator.diagnostics.map(\.message))")
    }

    /// Genuinely unknown identifiers are still errors (red line intact).
    func testGenuinelyUnknownStillErrors() throws {
        let evaluator = try evaluate("""
            import SwiftUI
            struct V: View {
                var body: some View { Text(totallyUnknownThing) }
            }
            """)
        let diags = evaluator.diagnostics.filter { $0.key == .diagUnknownIdentifier }
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.allSatisfy { $0.severity == .error })
    }

    /// A filled mock still wins over the requirement stub.
    func testFilledMockWins() throws {
        let engine = PreviewEngine(source: """
            import SwiftUI
            struct V: View {
                @StateObject var vm: HomeViewModel
                var body: some View { Text("hi") }
            }
            """)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        let store = PreviewMockStore()
        store.set(key: "vm", text: "mocked")
        evaluator.mockStore = store
        _ = try evaluator.renderRoot()
        // No NeedsMock for a filled requirement…
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error })
    }

    // MARK: - V36: ownerDisplayName end-to-end

    /// `ownerDisplayName` evaluates through the mocked `settings` to the
    /// `"老板"` fallback — no unknown-identifier error anywhere.
    func testV36OwnerDisplayNameFallsBack() throws {
        let index = try V36Acceptance.makeIndex()
        let (nodes, evaluator) = try V36Acceptance.evaluate(viewName: "HomeView", index: index)

        let errors = evaluator.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "HomeView must have no errors after regrading: \(errors.map(\.message))")
        XCTAssertTrue(texts(in: nodes).contains("老板"),
                      "ownerDisplayName must reach its fallback")
    }
}
