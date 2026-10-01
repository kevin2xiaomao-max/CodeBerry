import Foundation
import SwiftUI

/// §七 Mock data for preview: when a View depends on an `@EnvironmentObject`,
/// `@StateObject`, `Repository`/`ViewModel`/… (§七), the preview can't build it
/// — the user supplies values here instead. Keys are property names
/// (`store`) or qualified names (`PreviewHomeData.revenue`).
@Observable
final class PreviewMockStore {
    /// Raw values keyed by mock key.
    var values: [String: PreviewValue] = [:]

    var isEmpty: Bool { values.isEmpty }

    func value(for key: String) -> PreviewValue? { values[key] }

    /// Store a value from a text field: numbers and booleans are typed,
    /// everything else stays a string.
    func set(key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if trimmed.isEmpty {
            values.removeValue(forKey: key)
            return
        }
        if let d = Double(trimmed) {
            values[key] = .number(d)
        } else if trimmed == "true" {
            values[key] = .bool(true)
        } else if trimmed == "false" {
            values[key] = .bool(false)
        } else {
            values[key] = .string(trimmed)
        }
    }

    func text(for key: String) -> String {
        values[key]?.display ?? ""
    }

    func remove(key: String) {
        values.removeValue(forKey: key)
    }

    /// Insert an empty-string placeholder so a requirement reads as
    /// acknowledged even before the user types a value.
    func acknowledge(key: String) {
        guard values[key] == nil else { return }
        values[key] = .string("")
    }

    func reset() {
        values.removeAll()
    }
}
