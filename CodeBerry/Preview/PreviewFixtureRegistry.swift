import Foundation

/// 4.0.3 S9 (P0-G): in-memory registry of generated preview fixtures.
///
/// `revision` is the fixture dimension of the incremental-preview cache
/// fingerprint — every generate/register bumps it, forcing re-evaluation.
/// S12 (P0-J) builds the single fixture pipeline
/// (`plan → validate → generate → register`) on top of this registry.
final class PreviewFixtureRegistry {
    /// wrapperName → generated file source.
    private var fixtures: [String: String] = [:]

    /// Bumped on every register; read by the canvas for the fingerprint.
    private(set) var revision = 0

    func register(name: String, source: String) {
        fixtures[name] = source
        revision += 1
    }

    func source(for name: String) -> String? { fixtures[name] }

    var names: [String] { Array(fixtures.keys) }
}
