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
    }
    let kind: Kind
    /// Canonical text form (also what the evaluator consumes).
    let text: String
    /// For struct/array: field values.
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
}
