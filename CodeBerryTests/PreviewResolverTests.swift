import XCTest
@testable import CodeBerry

/// 4.0.3 S4 (P0-B): the unified symbol resolver.
///
/// Thin wrapper — the lookup order is unchanged, only unified. Unknown
/// static function calls on known types are never executed: they return a
/// preview default of the recorded return type (Info, never an error).
final class PreviewResolverTests: XCTestCase {

    private func resolver(for source: String) throws -> PreviewResolver {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        return PreviewResolver(document: doc, projectIndex: nil,
                               mockStore: nil, runtime: PreviewRuntime())
    }

    // MARK: - staticFunctions collection

    func testStaticFunctionsRecorded() throws {
        let resolver = try resolver(for: """
            import SwiftUI
            enum HomeInbox {
                static func items(limit: Int) -> [String] { [] }
                static func build() -> Int { 0 }
                static func reset() { }
            }
            """)
        let info = try XCTUnwrap(resolver.activeTypes["HomeInbox"])
        XCTAssertEqual(info.staticFunctions["items"], "[String]")
        XCTAssertEqual(info.staticFunctions["build"], "Int")
        XCTAssertEqual(info.staticFunctions["reset"], "Void")
    }

    func testInstanceMethodsNotRecorded() throws {
        let resolver = try resolver(for: """
            import SwiftUI
            struct Box {
                func open() -> Bool { true }
                static func make() -> Bool { true }
            }
            """)
        let info = try XCTUnwrap(resolver.activeTypes["Box"])
        XCTAssertNil(info.staticFunctions["open"])
        XCTAssertEqual(info.staticFunctions["make"], "Bool")
    }

    // MARK: - resolveStaticCall

    func testStaticCallApproximatesReturnType() throws {
        let resolver = try resolver(for: """
            import SwiftUI
            enum HomeInbox {
                static func items(limit: Int) -> [String] { [] }
            }
            """)
        let approx = try XCTUnwrap(
            resolver.resolveStaticCall(type: "HomeInbox", function: "items"))
        XCTAssertEqual(approx.display, "[]")
    }

    func testStaticCallUnknownFunctionReturnsNil() throws {
        let resolver = try resolver(for: """
            import SwiftUI
            enum HomeInbox {
                static func items(limit: Int) -> [String] { [] }
            }
            """)
        XCTAssertNil(resolver.resolveStaticCall(type: "HomeInbox", function: "nope"))
        XCTAssertNil(resolver.resolveStaticCall(type: "Nope", function: "items"))
    }

    // MARK: - resolveQualified (unified, behavior unchanged)

    func testResolveQualifiedLiteralStatic() throws {
        let resolver = try resolver(for: """
            import SwiftUI
            enum V32 {
                static let hero = Color.red
                static var pageBG: Color { Color.white }
            }
            """)
        let hero = try XCTUnwrap(resolver.resolveQualified(type: "V32", member: "hero"))
        if case .color = hero { } else {
            XCTFail("literal static must resolve directly, got \(hero)")
        }
        // Opaque static on an enum → member (enum-case-like).
        let bg = try XCTUnwrap(resolver.resolveQualified(type: "V32", member: "pageBG"))
        if case .member(let m) = bg { XCTAssertEqual(m, "pageBG") }
        else { XCTFail("expected .member, got \(bg)") }
    }

    func testResolveQualifiedUnknownReturnsNil() throws {
        let resolver = try resolver(for: "import SwiftUI\nstruct A { static let x = 1 }")
        XCTAssertNil(resolver.resolveQualified(type: "A", member: "nope"))
        XCTAssertNil(resolver.resolveQualified(type: "Nope", member: "x"))
    }

    // MARK: - resolve order (thin wrapper, unchanged behavior)

    func testResolveOrderLocalsFirst() throws {
        let resolver = try resolver(for: "import SwiftUI\nstruct V: View { var body: some View { Text(\"x\") } }")
        var env = PreviewEvaluator.Env(typeName: "V")
        env.locals["greeting"] = .string("local")
        if case .value(let v) = resolver.resolve("greeting", env: env) {
            XCTAssertEqual(v.display, "local")
        } else {
            XCTFail("locals must win")
        }
    }

    func testResolveUnknown() throws {
        let resolver = try resolver(for: "import SwiftUI\nstruct V: View { var body: some View { Text(\"x\") } }")
        let env = PreviewEvaluator.Env(typeName: "V")
        if case .unknown = resolver.resolve("definitelyNotHere", env: env) { } else {
            XCTFail("must be unknown")
        }
    }

    // MARK: - evaluator: HomeInbox.items is approximated, never executed

    func testV36HandlingItemsApproximatedNotExecuted() throws {
        let index = try V36Acceptance.makeIndex()
        let (_, evaluator) = try V36Acceptance.evaluate(viewName: "HomeView", index: index)

        let errors = evaluator.diagnostics.filter {
            $0.severity == .error &&
            ($0.params.contains("handlingItems") || $0.params.contains("HomeInbox"))
        }
        XCTAssertTrue(errors.isEmpty,
                      "handlingItems/HomeInbox must never error: \(errors.map(\.message))")
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagStaticCallApproximated &&
            $0.params.contains("HomeInbox.items")
        }, "static call approximation must be observable, got: \(evaluator.diagnostics.map(\.message))")
    }
}
