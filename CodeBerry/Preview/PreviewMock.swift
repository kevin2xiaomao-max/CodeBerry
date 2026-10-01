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

    /// 4.0.3 S9 (P0-G): bumped on every mutation — one dimension of the
    /// incremental-preview cache fingerprint. Mutate through `setValue`
    /// (or `set`/`remove`/`acknowledge`/`reset`), never by writing
    /// `values` directly, or the cache will serve stale previews.
    private(set) var revision = 0

    var isEmpty: Bool { values.isEmpty }

    func value(for key: String) -> PreviewValue? { values[key] }

    /// Write a value, bumping the revision. Prefer this over writing
    /// `values` directly.
    func setValue(_ value: PreviewValue, for key: String) {
        values[key] = value
        revision += 1
    }

    /// Store a value from a text field: numbers and booleans are typed,
    /// everything else stays a string.
    func set(key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if trimmed.isEmpty {
            values.removeValue(forKey: key)
            revision += 1
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
        revision += 1
    }

    func text(for key: String) -> String {
        values[key]?.display ?? ""
    }

    func remove(key: String) {
        values.removeValue(forKey: key)
        revision += 1
    }

    /// Insert an empty-string placeholder so a requirement reads as
    /// acknowledged even before the user types a value.
    func acknowledge(key: String) {
        guard values[key] == nil else { return }
        values[key] = .string("")
        revision += 1
    }

    func reset() {
        values.removeAll()
        revision += 1
    }
}
