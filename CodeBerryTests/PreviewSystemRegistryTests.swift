import XCTest
@testable import CodeBerry

/// 4.0.3 S2 (P0-D): the Foundation/system type registry.
///
/// The evaluator never executes real system APIs. Known system types get
/// safe approximations (pure values, no side effects, deterministic where
/// it matters); everything is `.info` severity — a system approximation
/// is never an error.
final class PreviewSystemRegistryTests: XCTestCase {

    // MARK: - Registry purity (no evaluator needed)

    func testStaticMemberCalendarCurrent() {
        let result = PreviewSystemRegistry.staticMember(of: "Calendar", name: "current")
        let (value, note) = try! XCTUnwrap(result)
        XCTAssertEqual(value.display, "Calendar")
        XCTAssertFalse(note.isEmpty)
    }

    func testStaticMemberLocaleCurrent() {
        let (value, _) = try! XCTUnwrap(
            PreviewSystemRegistry.staticMember(of: "Locale", name: "current"))
        XCTAssertEqual(value.display, "zh_CN")
    }

    func testStaticMemberUnknownTypeReturnsNil() {
        XCTAssertNil(PreviewSystemRegistry.staticMember(of: "ProcessInfo", name: "processInfo"))
        XCTAssertNil(PreviewSystemRegistry.staticMember(of: "Calendar", name: "bogusMember"))
    }

    func testConstructDateReturnsDateString() {
        let (value, note) = try! XCTUnwrap(
            PreviewSystemRegistry.construct(type: "Date", args: []))
        XCTAssertFalse(value.display.isEmpty)
        XCTAssertFalse(note.isEmpty)
    }

    func testConstructUUIDIsDeterministic() {
        let (a, _) = try! XCTUnwrap(PreviewSystemRegistry.construct(type: "UUID", args: []))
        let (b, _) = try! XCTUnwrap(PreviewSystemRegistry.construct(type: "UUID", args: []))
        // A fresh UUID per render would make previews flicker and tests flaky.
        XCTAssertEqual(a.display, b.display)
        XCTAssertEqual(a.display, PreviewSystemRegistry.fixedUUIDString())
    }

    func testConstructURLPassesStringThrough() {
        let (value, _) = try! XCTUnwrap(PreviewSystemRegistry.construct(
            type: "URL", args: [("string", .string("https://example.com"))]))
        XCTAssertEqual(value.display, "https://example.com")
    }

    func testConstructUnknownTypeReturnsNil() {
        XCTAssertNil(PreviewSystemRegistry.construct(type: "Timer", args: []))
    }

    func testCallComponentHourReturnsCurrentHour() {
        let (value, note) = try! XCTUnwrap(PreviewSystemRegistry.call(
            type: "Calendar", method: "component",
            args: [(nil, .member("hour")), ("from", .string("2026-10-02 10:00"))]))
        guard case .number(let hour) = value else {
            return XCTFail("component(.hour) must return a number, got \(value)")
        }
        XCTAssertTrue((0...23).contains(Int(hour)), "hour \(hour) out of range")
        XCTAssertFalse(note.isEmpty)
    }

    func testCallComponentOtherUnitApproximatesZero() {
        let (value, _) = try! XCTUnwrap(PreviewSystemRegistry.call(
            type: "Calendar", method: "component",
            args: [(nil, .member("weekday")), ("from", .string("2026-10-02 10:00"))]))
        guard case .number(let n) = value else {
            return XCTFail("expected number, got \(value)")
        }
        XCTAssertEqual(n, 0)
    }

    func testCallDateByAddingReturnsToDate() {
        let to = PreviewValue.string("2026-10-01 10:00")
        let (value, _) = try! XCTUnwrap(PreviewSystemRegistry.call(
            type: "Calendar", method: "date",
            args: [(nil, .member("day")), ("value", .number(-1)), ("to", to)]))
        XCTAssertEqual(value.display, to.display)
    }

    func testCallUnknownMethodReturnsNil() {
        XCTAssertNil(PreviewSystemRegistry.call(
            type: "Calendar", method: "enumerateDates", args: []))
    }

    func testMemberUUIDString() {
        let (value, _) = try! XCTUnwrap(
            PreviewSystemRegistry.member(of: "UUID", name: "uuidString"))
        XCTAssertEqual(value.display, PreviewSystemRegistry.fixedUUIDString())
    }

    func testKnownTypesCovered() {
        for t in ["Calendar", "Date", "Locale", "TimeZone", "UUID", "URL", "DateComponents"] {
            XCTAssertTrue(PreviewSystemRegistry.knownTypes.contains(t), "\(t) must be covered")
        }
    }

    // MARK: - Evaluator wiring

    private func render(_ source: String) throws
        -> (nodes: [PreviewViewNode], evaluator: PreviewEvaluator)
    {
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.fileName = "SystemView.swift"
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

    /// `UUID().uuidString` renders the fixed placeholder — info, never error.
    func testUUIDStringRendersPlaceholder() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct SysView: View {
                var body: some View { Text(UUID().uuidString) }
            }
            """)
        XCTAssertEqual(texts(in: nodes), [PreviewSystemRegistry.fixedUUIDString()])
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "system stubs must never error: \(evaluator.diagnostics.map(\.message))")
        XCTAssertTrue(evaluator.diagnostics.contains { $0.key == .diagSystemApproximation })
    }

    /// `Locale.current` renders; `Date()` binds without error.
    func testLocaleCurrentAndDateConstruction() throws {
        let (nodes, evaluator) = try render("""
            import SwiftUI
            struct SysView: View {
                var body: some View {
                    let d = Date()
                    Text(Locale.current)
                }
            }
            """)
        XCTAssertEqual(texts(in: nodes), ["zh_CN"])
        XCTAssertTrue(evaluator.diagnostics.allSatisfy { $0.severity != .error },
                      "system stubs must never error: \(evaluator.diagnostics.map(\.message))")
    }

    /// The same approximation key is computed once per evaluation pass —
    /// one preview never sees the hour flip mid-render.
    func testSystemApproximationMemoizedPerPass() {
        let evaluator = PreviewEvaluator(doc: PreviewDocument(), runtime: PreviewRuntime())
        var calls = 0
        let a = evaluator.systemApproximation(key: "k") { calls += 1; return .number(1) }
        let b = evaluator.systemApproximation(key: "k") { calls += 1; return .number(2) }
        XCTAssertEqual(calls, 1, "the factory must run exactly once per key")
        XCTAssertEqual(a.display, b.display)
    }
}
