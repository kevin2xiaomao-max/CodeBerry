import XCTest
@testable import CodeBerry

/// 4.0.2 P0-6: Mock Center type-aware defaults.
///
/// Regression context: every `@Environment` / `@Query` / Repository
/// requirement used to raise a mock-needed *error* until hand-filled —
/// including `modelContext` (never fillable by hand) and `reduceMotion`
/// (always false in preview). Now they auto-resolve by type.
final class PreviewMockTypeAwareTests: XCTestCase {

    private func req(_ property: String, _ type: String,
                     _ kind: PreviewMockRequirement.Kind = .dependency) -> PreviewMockRequirement {
        PreviewMockRequirement(propertyName: property, typeName: type, kind: kind)
    }

    // MARK: - typeAwareDefault

    func testReduceMotionDefaultsToFalse() {
        let v = MockCenter.typeAwareDefault(for: req("reduceMotion", "Bool", .environment))
        XCTAssertEqual(v?.kind, .bool)
        XCTAssertEqual(v?.previewValue().boolValue, false)
    }

    func testModelContextIsAStubNeverHandFilled() {
        let v = MockCenter.typeAwareDefault(
            for: req("modelContext", "ModelContext", .environment))
        XCTAssertEqual(v?.kind, .stub)
        if case .typeStub(let name) = v?.previewValue() {
            XCTAssertEqual(name, "ModelContext")
        } else {
            XCTFail("modelContext must bridge to a type stub")
        }
    }

    func testQueryArrayDefaultsToEmpty() {
        let v = MockCenter.typeAwareDefault(for: req("todos", "[Todo]", .query))
        XCTAssertEqual(v?.kind, .queryArray)
        if case .array(let items) = v?.previewValue() {
            XCTAssertTrue(items.isEmpty)
        } else {
            XCTFail("default @Query fill must be an empty array")
        }
    }

    func testQueryArraySampleAndCountModes() {
        let sample = MockValue.queryArray(elementType: "Todo", mode: .sample, count: 3)
        if case .array(let items) = sample.previewValue() {
            XCTAssertEqual(items.count, 3)
            XCTAssertTrue(items.allSatisfy { $0.display.hasPrefix("Sample Todo") })
        } else { XCTFail("sample mode must produce an array") }

        let counted = MockValue.queryArray(elementType: "Todo", mode: .count, count: 2)
        if case .array(let items) = counted.previewValue() {
            XCTAssertEqual(items.count, 2)
            XCTAssertFalse(items.first?.display.hasPrefix("Sample ") == true)
        } else { XCTFail("count mode must produce an array") }

        let empty = MockValue.queryArray(elementType: "Todo", mode: .empty)
        if case .array(let items) = empty.previewValue() {
            XCTAssertTrue(items.isEmpty)
        } else { XCTFail("empty mode must produce an empty array") }
    }

    func testEnvironmentDefaults() {
        XCTAssertEqual(
            MockCenter.typeAwareDefault(for: req("colorScheme", "ColorScheme", .environment))?.text,
            "light")
        XCTAssertEqual(
            MockCenter.typeAwareDefault(for: req("locale", "Locale", .environment))?.text,
            "current")
    }

    func testSettingsReadsDefault() {
        // "Settings 读默认/fixture": an empty struct default; an explicit
        // profile/fixture value wins (see testExplicitValuesWin).
        let v = MockCenter.typeAwareDefault(for: req("settings", "AppSettings"))
        XCTAssertEqual(v?.kind, .customStruct)
    }

    func testScalarFallbacks() {
        XCTAssertEqual(MockCenter.typeAwareDefault(for: req("flag", "Bool"))?.previewValue().boolValue, false)
        XCTAssertEqual(MockCenter.typeAwareDefault(for: req("name", "String"))?.previewValue().display, "")
    }

    func testTrulyUnknownDependenciesStillNeedHandFilling() {
        XCTAssertNil(MockCenter.typeAwareDefault(for: req("repo", "HomeRepository")))
        XCTAssertNil(MockCenter.typeAwareDefault(for: req("vm", "HomeViewModel")))
    }

    // MARK: - seeding

    func testSeedTypeAwareDefaultsFillsUnfilledOnly() {
        let store = PreviewMockStore()
        // Explicit (profile/fixture/user) values always win.
        store.values["todos"] = MockValue.queryArray(elementType: "Todo", mode: .count, count: 5).previewValue()

        MockCenter.seedTypeAwareDefaults(requirements: [
            req("todos", "[Todo]", .query),
            req("modelContext", "ModelContext", .environment),
            req("reduceMotion", "Bool", .environment),
            req("repo", "HomeRepository"),
        ], into: store)

        // Explicit count=5 preserved …
        if case .array(let items) = store.value(for: "todos") {
            XCTAssertEqual(items.count, 5)
        } else { XCTFail("explicit @Query fill must win") }
        // … auto-resolved kinds filled …
        XCTAssertNotNil(store.value(for: "modelContext"))
        XCTAssertEqual(store.value(for: "reduceMotion")?.boolValue, false)
        // … genuinely unknown dependencies still unfilled.
        XCTAssertNil(store.value(for: "repo"))
    }

    func testArrayElementTypeParsing() {
        XCTAssertEqual(MockCenter.arrayElementType(of: "[Todo]"), "Todo")
        XCTAssertEqual(MockCenter.arrayElementType(of: "Array<Todo>"), "Todo")
        XCTAssertNil(MockCenter.arrayElementType(of: "Todo"))
    }

    func testQueryFillModeRoundTrip() {
        let store = PreviewMockStore()
        store.values["todos"] = MockValue.queryArray(elementType: "Todo", mode: .sample, count: 4).previewValue()
        let sel = MockCenter.queryFillMode(in: store, for: "todos")
        XCTAssertEqual(sel.mode, .sample)
        XCTAssertEqual(sel.count, 4)

        store.values["empty"] = MockValue.queryArray(elementType: "Todo", mode: .empty).previewValue()
        XCTAssertEqual(MockCenter.queryFillMode(in: store, for: "empty").mode, .empty)
    }

    // MARK: - end-to-end: no mock-needed errors for auto-resolved kinds

    func testAutoResolvedRequirementsDoNotRaiseMockNeededErrors() throws {
        let source = """
        import SwiftUI
        import SwiftData
        struct Home: View {
            @Query var todos: [Todo]
            @Environment(\\.modelContext) var modelContext
            @Environment(\\.accessibilityReduceMotion) var reduceMotion
            var body: some View {
                Text("hi")
            }
        }
        """
        let engine = PreviewEngine(source: source)
        let parsed = try XCTUnwrap(engine.parseTree())
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: parsed.file)
        let reqs = doc.viewOrder.flatMap { doc.views[$0]?.mockRequirements ?? [] }
        XCTAssertEqual(reqs.count, 3, "all three requirements must be collected")

        // Same seeding the canvas performs in recompute().
        let store = PreviewMockStore()
        MockCenter.seedTypeAwareDefaults(requirements: reqs, into: store)

        let evaluator = PreviewEvaluator(doc: doc, runtime: PreviewRuntime())
        evaluator.converter = parsed.converter
        evaluator.mockStore = store
        _ = try evaluator.renderRoot()

        let mockErrors = evaluator.diagnostics.filter { $0.key == .diagMockNeeded }
        XCTAssertTrue(mockErrors.isEmpty,
                      "auto-resolved requirements must not error, got: \(mockErrors.map(\\.message))")
    }
}
