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
        var bodyHash: Int
        var nodes: [PreviewViewNode]
        var diagnosticsHash: Int
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
    static func evaluate(source: String,
                         fileName: String,
                         cache: inout Cache,
                         runtime: PreviewRuntime,
                         projectIndex: PreviewProjectIndex?,
                         mockStore: PreviewMockStore?)
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

        let identity = cacheKey(doc: doc, fileName: fileName)
        let diagHash = diagnosticsHash(of: evaluator.diagnostics)

        if let hit = cache.entries[identity.key],
           hit.bodyHash == identity.bodyHash,
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
            nodes = try evaluator.renderRoot()
        } catch {
            cache.evaluations += 1
            cache.totalNanos += DispatchTime.now().uptimeNanoseconds - started
            return ([], evaluator.diagnostics, stats(of: cache), evaluator)
        }
        cache.entries[identity.key] = Entry(
            bodyHash: identity.bodyHash,
            nodes: nodes,
            diagnosticsHash: diagnosticsHash(of: evaluator.diagnostics))
        cache.evaluations += 1
        cache.totalNanos += DispatchTime.now().uptimeNanoseconds - started
        return (nodes, evaluator.diagnostics, stats(of: cache), evaluator)
    }

    // MARK: - Identity

    /// (cache key, body hash) for the document's root view.
    static func cacheKey(doc: PreviewDocument, fileName: String) -> (key: String, bodyHash: Int) {
        let viewName: String
        if doc.previewBody != nil {
            viewName = "#Preview"
        } else {
            viewName = doc.viewOrder.first ?? fileName
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
