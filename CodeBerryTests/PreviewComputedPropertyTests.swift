import XCTest
@testable import CodeBerry

/// 4.0.3 S3 (P0-A): ordinary computed property semantic model.
///
/// Pure getters are evaluated for their value; getters with possible side
/// effects become NeedsMock warnings with a preview default from the
/// declared return type; cycles become warnings, never hangs.
final class PreviewComputedPropertyTests: XCTestCase {

    private func render(_ source: String) throws
        -> (nodes: [PreviewViewNode], evaluator: PreviewEvaluator)
    {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.fileName = "CPView.swift"
        evaluator.converter = parsed.converter
        return (try evaluator.renderRoot(), evaluator)
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

    /// Pure getter with `let` + if/return evaluates to its value.
    func testPureGetterEvaluates() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct CPView: View {
                var greeting: String {
                    let hour = 10
                    if hour < 11 { return "早上好" }
                    return "晚上好"
                }
                var body: some View { Text(greeting) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["早上好"])
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "\(evaluator.diagnostics.map(\.message))")
    }

    /// if / else-if / else chains pick the right branch.
    func testIfElseIfChain() throws {
        let (nodes, _) = try render("""
            import SwiftUI
            struct CPView: View {
                var level: String {
                    let score = 85
                    if score >= 90 { return "优" }
                    else if score >= 60 { return "良" }
                    else { return "差" }
                }
                var body: some View { Text(level) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["良"])
    }

    /// `if let` bindings work inside getters.
    func testIfLetBinding() throws {
        let (nodes, _) = try render("""
            import SwiftUI
            struct CPView: View {
                var nickname: String {
                    let name: String? = "小猪"
                    if let n = name { return n }
                    return "匿名"
                }
                var body: some View { Text(nickname) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["小猪"])
    }

    /// Single-expression getter uses the implicit return.
    func testImplicitReturn() throws {
        let (nodes, _) = try render("""
            import SwiftUI
            struct CPView: View {
                var displayName: String { "老板" }
                var body: some View { Text(displayName) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["老板"])
    }

    /// Ternary expressions evaluate inside getters.
    func testTernaryInGetter() throws {
        let (nodes, _) = try render("""
            import SwiftUI
            struct CPView: View {
                var label: String {
                    let empty = false
                    return empty ? "空" : "有数据"
                }
                var body: some View { Text(label) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["有数据"])
    }

    /// Assignment in the getter → side effects → NeedsMock + Int default.
    func testSideEffectGetterBecomesNeedsMock() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct CPView: View {
                @State private var count = 0
                var doubled: Int {
                    count += 1
                    return count * 2
                }
                var body: some View { Text("v\\(doubled)") }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["v0"],
                       "side-effect getter must approximate with the Int default")
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.severity == .warning && $0.key == .diagComputedPropertyNeedsMock
        }, "must warn NeedsMock, got: \(evaluator.diagnostics.map(\.message))")
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error })
    }

    /// `self.`-qualified calls count as side effects.
    func testSelfCallGetterBecomesNeedsMock() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct CPView: View {
                var token: String {
                    self.refresh()
                    return "x"
                }
                func refresh() {}
                var body: some View { Text(token) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), [""],
                       "side-effect getter must approximate with the String default")
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagComputedPropertyNeedsMock
        })
    }

    /// Mutually recursive computed properties warn instead of hanging.
    func testCyclicComputedPropertiesWarn() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct CPView: View {
                var a: Int { b }
                var b: Int { a }
                var body: some View { Text("v\\(a)") }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["v0"])
        XCTAssertTrue(evaluator.diagnostics.contains {
            $0.key == .diagComputedPropertyNeedsMock
        }, "cycle must warn, got: \(evaluator.diagnostics.map(\.message))")
    }

    /// A computed property chain (`a` reads `b`) evaluates through.
    func testChainedComputedProperties() throws {
        let (nodes, _) = try render("""
            import SwiftUI
            struct CPView: View {
                var base: Int { 21 }
                var doubled: Int { base * 2 }
                var body: some View { Text("v\\(doubled)") }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["v42"])
    }

    // MARK: - V36 acceptance: the real greetingPrefix getter

    /// `greetingPrefix` (Calendar + if/else-if chain) evaluates — no
    /// unknown-identifier error — and the header shows a real greeting.
    func testV36GreetingPrefixEvaluates() throws {
        let index = try V36Acceptance.makeIndex()
        let (nodes, evaluator) = try V36Acceptance.evaluate(viewName: "HomeView", index: index)

        let greetingErrors = evaluator.diagnostics.filter {
            $0.severity == .error && $0.params.contains("greetingPrefix")
        }
        XCTAssertTrue(greetingErrors.isEmpty,
                      "greetingPrefix must not be an unknown identifier: \(greetingErrors.map(\.message))")

        let greetings = ["早上好", "中午好", "下午好", "晚上好"]
        XCTAssertTrue(texts(in: nodes).contains(where: greetings.contains),
                      "the header must show the evaluated greeting")
    }
}
