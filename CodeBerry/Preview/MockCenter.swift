import Foundation
import SwiftUI

// MARK: - M3 §17 Mock Center
//
// Project-level mocks: String / Int / Double / Bool / Color / Date /
// simple struct / array / preview-only environment values.
//
// Profiles (§17): Home / Normal, Home / Empty, Home / Busy, Home / Dark.
//
// Hard rule: Mock Center NEVER executes real network, a SwiftData DB, or
// repository side effects. Values are pure data; the evaluator only reads
// them for `@State`-seeded previews and `PreviewMockRequirement`s.

struct MockValue: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case string, int, double, bool, color, date, customStruct, array
        /// 4.0.2 P0-6: an auto-resolved stub that never needs hand-filling
        /// (e.g. `modelContext`). The evaluator treats it as a silent no-op.
        case stub
        /// 4.0.2 P0-6: a `@Query` array with an explicit fill mode
        /// (Empty / Sample / Count). `text` holds the element type name.
        case queryArray
    }
    let kind: Kind
    /// Canonical text form (also what the evaluator consumes).
    let text: String
    /// For struct/array: field values.
    /// For queryArray: `["mode": .string("sample"), "count": .int(3)]`.
    let fields: [String: MockValue]

    init(kind: Kind, text: String, fields: [String: MockValue] = [:]) {
        self.kind = kind; self.text = text; self.fields = fields
    }

    static func string(_ s: String) -> MockValue { .init(kind: .string, text: s) }
    static func int(_ i: Int) -> MockValue { .init(kind: .int, text: "\(i)") }
    static func double(_ d: Double) -> MockValue { .init(kind: .double, text: "\(d)") }
    static func bool(_ b: Bool) -> MockValue { .init(kind: .bool, text: b ? "true" : "false") }
    static func color(hex: String) -> MockValue { .init(kind: .color, text: hex) }
    static func date(_ iso: String) -> MockValue { .init(kind: .date, text: iso) }

    /// 4.0.2 P0-6: a stub that auto-resolves (never hand-filled).
    static func stub(_ name: String) -> MockValue { .init(kind: .stub, text: name) }

    /// 4.0.2 P0-6: `@Query` array fill modes — Empty / Sample / Count.
    enum QueryArrayMode: String, Hashable, Sendable {
        case empty, sample, count
    }

    /// 4.0.2 P0-6: a `@Query var x: [T]` mock with an explicit fill mode.
    /// `count` is the Sample/Count size (ignored for Empty).
    static func queryArray(elementType: String,
                           mode: QueryArrayMode, count: Int = 0) -> MockValue {
        .init(kind: .queryArray, text: elementType,
              fields: ["mode": .string(mode.rawValue), "count": .int(count)])
    }

    /// Bridge into the existing evaluator value type.
    func previewValue() -> PreviewValue {
        switch kind {
        case .string: return .string(text)
        case .int: return .number(Double(text) ?? 0)
        case .double: return .number(Double(text) ?? 0)
        case .bool: return .bool(text == "true")
        case .color: return .string(text)   // evaluator resolves hex/CSS names at render
        case .date: return .string(text)
        case .customStruct: return .string(text)
        case .array: return .string(text)
        case .stub:
            // A type stub: member access / calls on it are silent no-ops.
            return .typeStub(text)
        case .queryArray:
            let mode = QueryArrayMode(rawValue: fields["mode"]?.text ?? "") ?? .empty
            let count = Int(fields["count"]?.text ?? "") ?? 0
            guard mode != .empty, count > 0 else { return .array([]) }
            let prefix = mode == .sample ? "Sample " : ""
            return .array((1...count).map { .string("\(prefix)\(text) \($0)") })
        }
    }
}

/// One named profile, e.g. "Home / Empty".
struct MockProfile: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    /// Keyed "ViewName.property" or bare "property" (fallback for any view).
    var values: [String: MockValue]
    var darkMode: Bool

    init(id: String = UUID().uuidString, displayName: String,
         values: [String: MockValue] = [:], darkMode: Bool = false) {
        self.id = id; self.displayName = displayName
        self.values = values; self.darkMode = darkMode
    }

    func value(view: String, property: String) -> MockValue? {
        values["\(view).\(property)"] ?? values[property]
    }
}

/// Project-level mock store. Deliberately NOT @MainActor: the canvas calls
/// `apply(to:)` from nonisolated view closures; all access happens on the
/// main thread via SwiftUI in practice.
@Observable
final class MockCenter {
    var profiles: [MockProfile]
    var activeProfileID: String?

    init(profiles: [MockProfile]? = nil) {
        let resolved = profiles ?? Self.builtInProfiles()
        self.profiles = resolved
        self.activeProfileID = resolved.first?.id
    }

    var activeProfile: MockProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    func value(view: String, property: String) -> MockValue? {
        activeProfile?.value(view: view, property: property)
    }

    func setValue(_ value: MockValue?, view: String, property: String) {
        let key = view.isEmpty ? property : "\(view).\(property)"
        setQualifiedValue(value, forKey: key)
    }

    /// Write directly to a qualified ("ViewName.property") or bare key.
    func setQualifiedValue(_ value: MockValue?, forKey key: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        if let value { profiles[idx].values[key] = value }
        else { profiles[idx].values.removeValue(forKey: key) }
    }

    func addProfile(named name: String) {
        let base = activeProfile
        profiles.append(MockProfile(displayName: name,
                                    values: base?.values ?? [:],
                                    darkMode: base?.darkMode ?? false))
        activeProfileID = profiles.last?.id
    }

    func removeProfile(id: String) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles.first?.id }
    }

    /// §17 built-ins. Home-flavoured because the spec's canonical example is
    /// HomeView with SwiftData/Repository blocked.
    static func builtInProfiles() -> [MockProfile] {
        [
            MockProfile(displayName: "Home / Normal", values: [
                "HomeView.revenue": .double(128_400),
                "HomeView.userName": .string("老板"),
                "HomeView.todoCount": .int(7),
                "HomeView.isBusy": .bool(false),
            ]),
            MockProfile(displayName: "Home / Empty", values: [
                "HomeView.revenue": .double(0),
                "HomeView.userName": .string(""),
                "HomeView.todoCount": .int(0),
                "HomeView.isBusy": .bool(false),
            ]),
            MockProfile(displayName: "Home / Busy", values: [
                "HomeView.revenue": .double(987_654),
                "HomeView.userName": .string("老板"),
                "HomeView.todoCount": .int(42),
                "HomeView.isBusy": .bool(true),
            ]),
            MockProfile(displayName: "Home / Dark", values: [
                "HomeView.revenue": .double(128_400),
                "HomeView.userName": .string("老板"),
                "HomeView.todoCount": .int(7),
                "HomeView.isBusy": .bool(false),
            ], darkMode: true),
        ]
    }

    /// Push the active profile into the evaluator's per-preview mock store.
    /// Keys match `PreviewMockRequirement` conventions (property or
    /// qualified name) — pure data copy, zero side effects.
    func apply(to store: PreviewMockStore) {
        store.reset()
        for (key, value) in activeProfile?.values ?? [:] {
            let property = key.components(separatedBy: ".").last ?? key
            store.values[property] = value.previewValue()
            store.values[key] = value.previewValue()
        }
    }

    // MARK: - 4.0.2 P0-6: type-aware defaults

    /// The type-aware default for one mock requirement, or nil when the
    /// requirement genuinely needs hand-filling. Never executes user code,
    /// never touches the network, SwiftData, or live UserDefaults.
    ///
    /// Resolution order used by the canvas: explicit profile/fixture value
    /// first, then this default ("Settings 读默认/fixture").
    static func typeAwareDefault(for requirement: PreviewMockRequirement) -> MockValue? {
        let name = requirement.propertyName.lowercased()
        let type = requirement.typeName

        // reduceMotion → Bool false, always (preview shows full motion).
        if name.contains("reducemotion") { return .bool(false) }

        // modelContext is never hand-filled — a silent stub.
        if name.contains("modelcontext") || type.contains("ModelContext") {
            return .stub("ModelContext")
        }

        switch requirement.kind {
        case .query:
            // @Query arrays: Empty by default; the Mock sheet offers
            // Empty / Sample / Count.
            let element = arrayElementType(of: type) ?? "Item"
            return .queryArray(elementType: element, mode: .empty)
        case .environment:
            if let envDefault = environmentDefault(property: name, type: type) {
                return envDefault
            }
        default:
            break
        }

        // Settings-like types read defaults/fixture: an empty struct default
        // here; a profile/fixture value wins when present (see
        // seedTypeAwareDefaults — explicit values are never overwritten).
        if type.contains("Settings") {
            return MockValue(kind: .customStruct, text: type)
        }

        // Fall back to the declared scalar type, if any.
        switch type.trimmingCharacters(in: .whitespaces) {
        case "Bool": return .bool(false)
        case "String": return .string("")
        case "Int": return .int(0)
        case "Double", "Float", "CGFloat": return .double(0)
        default: return nil
        }
    }

    /// Well-known `@Environment` values get their preview defaults.
    private static func environmentDefault(property lowercasedName: String,
                                           type: String) -> MockValue? {
        switch lowercasedName {
        case "colorscheme": return .string("light")
        case "locale": return .string("current")
        case "sizecategory": return .string("medium")
        case "legibilityweight": return .string("regular")
        case "colorschemecontrast": return .string("standard")
        case "layoutdirection": return .string("leftToRight")
        case "accessibilityreducetransparency",
             "accessibilitydifferentiatewithoutcolor",
             "accessibilityinvertcolors":
            return .bool(false)
        default: return nil
        }
    }

    /// `"[Todo]"` → `"Todo"`, `"Array<Todo>"` → `"Todo"`.
    static func arrayElementType(of typeName: String) -> String? {
        let t = typeName.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[") && t.hasSuffix("]") {
            let inner = t.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            return inner.isEmpty ? nil : inner
        }
        if t.hasPrefix("Array<") && t.hasSuffix(">") {
            let inner = t.dropFirst("Array<".count).dropLast().trimmingCharacters(in: .whitespaces)
            return inner.isEmpty ? nil : inner
        }
        return nil
    }

    /// Seed type-aware defaults into a mock store for requirements that have
    /// them. Explicit values (profile / fixture / user-typed) always win —
    /// only unfilled requirements are touched. Called by the canvas before
    /// every evaluation so auto-resolved requirements (modelContext, @Query,
    /// reduceMotion, environment defaults) never raise mock-needed errors
    /// and never need hand-filling.
    static func seedTypeAwareDefaults(requirements: [PreviewMockRequirement],
                                      into store: PreviewMockStore) {
        for req in requirements where store.value(for: req.propertyName) == nil {
            if let auto = typeAwareDefault(for: req) {
                store.values[req.propertyName] = auto.previewValue()
            }
        }
    }

    /// Current @Query fill selection for the Mock sheet
    /// (Empty / Sample / Count), recovered from the stored array.
    static func queryFillMode(in store: PreviewMockStore,
                              for key: String) -> (mode: MockValue.QueryArrayMode, count: Int) {
        guard case .array(let items) = store.value(for: key), !items.isEmpty else {
            return (.empty, 0)
        }
        let isSample = items.first?.display.hasPrefix("Sample ") == true
        return (isSample ? .sample : .count, items.count)
    }
}
