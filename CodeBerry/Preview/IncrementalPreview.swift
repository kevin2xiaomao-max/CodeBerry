import Foundation
import SwiftParser
import SwiftSyntax

/// M3 §16 Incremental Preview: only re-evaluate views whose AST identity
/// changed since the last pass.
///
/// Identity = hash of the view's `body` source range. On a cache hit the
/// previously rendered nodes are reused and `evaluate` returns immediately;
/// when the source has syntax/semantic errors the cache is bypassed and a
/// full evaluation runs (errors must always be recomputed fresh).
enum IncrementalPreview {

    /// Per-view cache entry. `@unchecked` because PreviewViewNode carries a
    /// button-action closure; entries are confined to the main actor in practice.
    struct Entry: @unchecked Sendable {
        var fingerprint: Fingerprint
        var nodes: [PreviewViewNode]
        var diagnosticsHash: Int
    }

    /// 4.0.3 S9 (P0-G): 6-dimensional cache fingerprint. A hit requires ALL
    /// dimensions to match — a change in any one forces re-evaluation, so
    /// stale previews are never served.
    struct Fingerprint: Hashable, Sendable {
        /// Hash of the target view's body source.
        var sourceRevision: Int
        /// S8: the explicit selection (PreviewCandidate.viewName).
        var targetViewName: String
        /// PreviewProjectIndex.generation — cross-file dependencies.
        var indexGeneration: Int
        /// PreviewMockStore.revision — mock values + active profile.
        var mockRevision: Int
        /// PreviewRuntime.version — @State changes.
        var runtimeRevision: Int
        /// PreviewFixtureRegistry.revision — generated fixtures.
        var fixtureRevision: Int
    }

    /// The cache. Lives in the canvas as `@State`; keyed by view name.
    /// `@unchecked` for the same reason as Entry (main-actor confined).
    struct Cache: @unchecked Sendable {
        var entries: [String: Entry] = [:]
        var hits: Int = 0
        var misses: Int = 0
        var totalNanos: UInt64 = 0
        var evaluations: Int = 0

        /// Hit rate over the session (0 when nothing evaluated yet).
        var hitRate: Double {
            let total = hits + misses
            return total == 0 ? 0 : Double(hits) / Double(total)
        }

        /// Mean evaluation time in milliseconds.
        var meanMillis: Double {
            evaluations == 0 ? 0 : Double(totalNanos) / Double(evaluations) / 1_000_000
        }

        mutating func reset() {
            entries = [:]; hits = 0; misses = 0; totalNanos = 0; evaluations = 0
        }
    }

    /// Debug counters surfaced in the canvas (debug 面板可看).
    struct Stats: Sendable {
        var hits: Int
        var misses: Int
        var hitRate: Double
        var meanMillis: Double
    }

    // MARK: - Entry point

    /// Evaluate `source`, reusing cached view nodes when the view's body
    /// AST identity is unchanged. Returns the rendered nodes, diagnostics,
    /// debug stats, and the evaluator (kept alive by the canvas for
    /// `mockRequirements` / `activeViews`).
    ///
    /// 4.0.3 S8 (P0-F): `targetView` is the user's explicit selection
    /// (PreviewCandidate.viewName), threaded end to end — never
    /// `viewOrder.first` by default.
    static func evaluate(source: String,
                         fileName: String,
                         cache: inout Cache,
                         runtime: PreviewRuntime,
                         projectIndex: PreviewProjectIndex?,
                         mockStore: PreviewMockStore?,
                         targetView: String? = nil,
                         fixtureRevision: Int = 0)
        -> (nodes: [PreviewViewNode], diagnostics: [PreviewDiagnostic],
            stats: Stats, evaluator: PreviewEvaluator)
    {
        let started = DispatchTime.now().uptimeNanoseconds

        let engine = PreviewEngine(source: source)
        guard let (file, converter) = engine.parseTree() else {
            // Unparseable: full stop, no cache.
            cache.misses += 1
            let evaluator = PreviewEvaluator(doc: PreviewDocument(), runtime: runtime)
            return ([], evaluator.diagnostics, stats(of: cache), evaluator)
        }
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: file)

        let evaluator = PreviewEvaluator(doc: doc, runtime: runtime)
        evaluator.fileName = fileName
        evaluator.converter = converter
        evaluator.projectIndex = projectIndex
        evaluator.mockStore = mockStore

        let identity = cacheKey(doc: doc, fileName: fileName, targetView: targetView)
        let diagHash = diagnosticsHash(of: evaluator.diagnostics)

        // 4.0.3 S9 (P0-G): 6-dimensional fingerprint — every dimension
        // must match for a hit.
        let fingerprint = Fingerprint(
            sourceRevision: identity.bodyHash,
            targetViewName: identity.viewName,
            indexGeneration: projectIndex?.generation ?? 0,
            mockRevision: mockStore?.revision ?? 0,
            runtimeRevision: runtime.version,
            fixtureRevision: fixtureRevision)

        if let hit = cache.entries[identity.key],
           hit.fingerprint == fingerprint,
           hit.diagnosticsHash == diagHash {
            cache.hits += 1
            cache.evaluations += 1
            cache.totalNanos += DispatchTime.now().uptimeNanoseconds - started
            return (hit.nodes, evaluator.diagnostics, stats(of: cache), evaluator)
        }

        // Miss or identity changed: full evaluation.
        cache.misses += 1
        let nodes: [PreviewViewNode]
        do {
            nodes = try evaluator.renderRoot(targetView: targetView)
        } catch {
            cache.evaluations += 1
            cache.totalNanos += DispatchTime.now().uptimeNanoseconds - started
            return ([], evaluator.diagnostics, stats(of: cache), evaluator)
        }
        cache.entries[identity.key] = Entry(
            fingerprint: fingerprint,
            nodes: nodes,
            diagnosticsHash: diagnosticsHash(of: evaluator.diagnostics))
        cache.evaluations += 1
        cache.totalNanos += DispatchTime.now().uptimeNanoseconds - started
        return (nodes, evaluator.diagnostics, stats(of: cache), evaluator)
    }

    // MARK: - Identity

    /// (cache key, body hash) for the document's root view.
    ///
    /// 4.0.3 S8 (P0-F): the key records the explicit target — never
    /// `viewOrder.first` by default. An ambiguous (multi-view, no target)
    /// document keys as "#Ambiguous" so a later explicit selection can't
    /// hit a stale entry.
    static func cacheKey(doc: PreviewDocument, fileName: String, targetView: String? = nil) -> (key: String, bodyHash: Int, viewName: String) {
        let viewName: String
        if doc.previewBody != nil {
            viewName = "#Preview"
        } else if let target = targetView {
            viewName = target
        } else if doc.viewOrder.count == 1 {
            viewName = doc.viewOrder[0]
        } else {
            viewName = "#Ambiguous"
        }
        let bodyText: String
        if let view = doc.views[viewName], let body = view.bodyStatements {
            bodyText = body.trimmedDescription
        } else if viewName == "#Preview", let previewBody = doc.previewBody {
            bodyText = previewBody.trimmedDescription
        } else {
            bodyText = viewName
        }
        var hasher = Hasher()
        hasher.combine(fileName)
        hasher.combine(viewName)
        hasher.combine(bodyText)
        return (key: "\(fileName)#\(viewName)", bodyHash: hasher.finalize())
    }

    static func diagnosticsHash(of diagnostics: [PreviewDiagnostic]) -> Int {
        var hasher = Hasher()
        for d in diagnostics {
            hasher.combine(d.severity)
            hasher.combine(d.key.rawValue)
            hasher.combine(d.message)
            hasher.combine(d.line ?? -1)
        }
        return hasher.finalize()
    }

    private static func stats(of cache: Cache) -> Stats {
        Stats(hits: cache.hits, misses: cache.misses,
              hitRate: cache.hitRate, meanMillis: cache.meanMillis)
    }
}
