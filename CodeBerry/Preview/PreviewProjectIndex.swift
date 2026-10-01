import Foundation
import SwiftSyntax

/// One design token extracted from source: a top-level `let` or a
/// `static let` inside a type, e.g. `let brand = Color(...)` or
/// `V32Layout.sectionGap`.
struct PreviewToken {
    enum Kind {
        case color, number, string, bool

        init?(of value: PreviewValue) {
            switch value {
            case .color: self = .color
            case .number: self = .number
            case .string: self = .string
            case .bool: self = .bool
            default: return nil
            }
        }
    }

    let qualifiedName: String
    let kind: Kind
    let value: PreviewValue
    let file: String
    let line: Int
    /// UTF-8 offsets of the whole `let` declaration — used by the Inspector
    /// to rewrite the token definition (§三, §六).
    let declStartOffset: Int
    let declEndOffset: Int
}

// MARK: - 4.0.2 P0-1: unified project-index policy
//
// `ProjectAnalyzer.maxFiles` (1000) and `PreviewProjectIndex.maxFiles` (100)
// disagreed, so the readiness list could name files the preview index never
// parsed (V35/V36 components in a 233-file project fell past the cap and
// rendered as `[?]`). One policy now governs both; the preview index
// additionally runs incrementally (content-hash gated), on a background
// thread for cold starts, cancellable, with the current file parsed first.

/// Single source of truth for project-index limits (4.0.2 P0-1).
enum ProjectIndexPolicy {
    /// Max Swift files indexed per project. Matches the analyzer so the
    /// readiness list and the preview index never disagree on coverage.
    static let maxFiles = 1000
    /// Files parsed per background batch; each batch checks cancellation.
    static let backgroundBatchSize = 25
}

// MARK: - 4.0.2 P0-3: cross-file ordinary types
//
// The old index only knew `struct X: View`. Real projects reference ordinary
// types across files (`DemoMode.shared.isEnabled`, `DemoCatalog.monthlyRevenue`)
// which the evaluator reported as unknown-identifier errors. The index now
// records every class/struct/enum/actor with its static members and instance
// member type annotations — never executing anything — so member access
// falls back to preview defaults instead of erroring.

/// Cross-file ordinary type info (4.0.2 P0-3).
struct PreviewTypeInfo {
    enum Kind: String {
        case `class`, `struct`, `enum`, actor
    }
    let name: String
    let kind: Kind
    let filePath: String
    /// `static let` members with safely-evaluated literal values.
    let staticValues: [String: PreviewValue]
    /// Static members that exist but can't be safely evaluated
    /// (non-literal initializers, side effects, self-references like
    /// `static let shared = DemoMode()`).
    let opaqueStatics: Set<String>
    /// Instance `var`/`let` members: name → declared type annotation.
    let instanceMembers: [String: String]
    /// 4.0.3 S4 (P0-B): `static func` members: name → declared return type.
    /// Calls are never executed — the evaluator returns a preview default
    /// of the recorded return type instead.
    let staticFunctions: [String: String]
    /// `static let shared` / `static var shared` singleton pattern.
    var isSingleton: Bool {
        opaqueStatics.contains("shared") || staticValues["shared"] != nil
    }
}

/// §二 Multi-file preview: a project-wide index of View structs and design
/// tokens. Incremental — each file is fingerprinted, only changed files are
/// re-parsed. Capped at `ProjectIndexPolicy.maxFiles` so huge projects can't
/// stall the canvas.
///
/// 4.0.2 P0-1 / P1-11: cold-start indexing runs on a background thread
/// (`rebuildInBackground`, cancellable via the hosting `.task`, current file
/// first); warm passes stay synchronous but hash-gated, so per-keystroke work
/// is O(changed files), never a full re-parse.
@Observable
final class PreviewProjectIndex {
    /// 4.0.2 P0-1: unified with `ProjectAnalyzer` via `ProjectIndexPolicy`.
    static var maxFiles: Int { ProjectIndexPolicy.maxFiles }

    struct IndexedFile {
        let path: String
        let hash: UInt64
        let views: [String: PreviewViewStruct]
        let tokens: [PreviewToken]
        /// 4.0.2 P0-3: ordinary types by name.
        let types: [String: PreviewTypeInfo]
    }

    private var files: [String: IndexedFile] = [:]
    private var fingerprints: [String: UInt64] = [:]
    /// 4.0.2 P1-11: mtime/size pre-filter so warm passes skip unchanged
    /// files without even reading+hashing them.
    private var fileMeta: [String: FileMeta] = [:]

    /// Cheap stat snapshot used as a pre-filter before read+hash.
    struct FileMeta: Equatable, Sendable {
        let mtime: Date
        let size: Int
    }

    /// All Views in the project: name → (defining file, struct).
    private(set) var viewsByName: [String: (file: String, view: PreviewViewStruct)] = [:]
    /// All design tokens: qualified name → token.
    private(set) var tokensByName: [String: PreviewToken] = [:]
    /// 4.0.2 P0-3: all ordinary types: name → info.
    private(set) var typesByName: [String: PreviewTypeInfo] = [:]

    /// 4.0.3 S1: index-time diagnostics (same-name symbol conflicts, …).
    /// Surfaced by the acceptance harness and the canvas diagnostics panel.
    private(set) var indexDiagnostics: [PreviewDiagnostic] = []

    /// 4.0.3 S9 (P0-G): bumped whenever index content actually changes.
    /// One dimension of the incremental-preview cache fingerprint.
    private(set) var generation = 0

    /// Progress UI (§二: "正在建立预览索引").
    var isIndexing = false
    var indexedCount = 0
    var totalCount = 0

    // MARK: - Incremental update (warm path, synchronous)

    /// Incremental update: lists files, then only (re-)parses files whose
    /// content hash changed since the last pass. Files whose mtime/size
    /// are unchanged skip even the read+hash; unchanged entries are kept,
    /// so per-keystroke work is O(changed), not O(project).
    ///
    /// - Parameters:
    ///   - currentPath: workspace path of the file open in the editor.
    ///   - currentSource: its live in-memory source (wins over disk).
    ///   - readFile: reads any other workspace file's content.
    func update(projectRoot: URL,
                projectName: String,
                currentPath: String?,
                currentSource: String,
                readFile: (String) -> String?) {
        let listed = Self.swiftFiles(under: projectRoot, projectName: projectName)
        totalCount = listed.count
        // Current file first: it decides what the canvas renders.
        let ordered = Self.currentFileFirst(listed, currentPath: currentPath)
        var rebuilt = false
        var live = Set<String>()
        live.reserveCapacity(ordered.count)
        for item in ordered {
            let path = item.path
            live.insert(path)
            if path == currentPath {
                // The live in-memory buffer always wins for the current
                // file; disk mtime can't be trusted for unsaved edits.
                fileMeta[path] = item.meta
                let hash = Self.hash(currentSource)
                if fingerprints[path] == hash { continue }
                index(path: path, source: currentSource, hash: hash)
                rebuilt = true
                continue
            }
            // 4.0.2 P1-11 mtime/size pre-filter: unchanged files skip
            // even the read+hash; only stat-changed files are read.
            if fileMeta[path] == item.meta { continue }
            guard let content = readFile(path) else {
                // Unreadable (deleted mid-pass): drop any stale entry.
                if files.removeValue(forKey: path) != nil { rebuilt = true }
                fingerprints.removeValue(forKey: path)
                fileMeta.removeValue(forKey: path)
                continue
            }
            let hash = Self.hash(content)
            fileMeta[path] = item.meta
            if fingerprints[path] == hash { continue }  // mtime-only touch
            index(path: path, source: content, hash: hash)
            rebuilt = true
        }
        // Drop deleted files.
        for path in files.keys where !live.contains(path) {
            files.removeValue(forKey: path)
            fingerprints.removeValue(forKey: path)
            fileMeta.removeValue(forKey: path)
            rebuilt = true
        }
        if rebuilt { rebuildLookup() }
        indexedCount = live.count
        // 4.0.3 S9 (P0-G): bump the generation only when index content
        // actually changed — the cache fingerprint's index dimension.
        if rebuilt { generation += 1 }
    }

    // MARK: - Background rebuild (cold path)

    /// Cold-start indexing on a background thread (4.0.2 P0-1): file contents
    /// are snapshotted on the caller (because `readFile` touches
    /// MainActor-isolated store state), then changed files parse in
    /// cancellable background batches. The current file parses first so the
    /// canvas never waits on the background pass for the file being edited.
    /// Results merge back on the caller's actor; `self` is never touched
    /// off-thread.
    ///
    /// 4.0.2 P1-11: MainActor-isolated by design — the snapshot phase
    /// reads MainActor-isolated store state (`readFile`), and only the
    /// parse batches escape to a detached task. This also keeps the
    /// `await` call in `PreviewCanvasView.updateIndex` free of Swift 6
    /// `sending` data-race errors.
    @MainActor
    func rebuildInBackground(projectRoot: URL,
                             projectName: String,
                             currentPath: String?,
                             currentSource: String,
                             readFile: (String) -> String?) async {
        let listed = Self.swiftFiles(under: projectRoot, projectName: projectName)
        totalCount = listed.count
        let ordered = Self.currentFileFirst(listed, currentPath: currentPath)
        // Snapshot (path, content) pairs on the caller's actor. fileMeta is
        // only READ here (pre-filter); it is WRITTEN in the merge below,
        // so a cancelled pass never marks unparsed files as done.
        var snapshot: [ParseSnapshot] = []
        snapshot.reserveCapacity(ordered.count)
        for item in ordered {
            let path = item.path
            if path == currentPath {
                let hash = Self.hash(currentSource)
                if fingerprints[path] == hash { continue }  // already indexed
                snapshot.append(ParseSnapshot(path: path, content: currentSource,
                                              hash: hash, meta: item.meta))
                continue
            }
            // 4.0.2 P1-11: same mtime/size pre-filter as the warm pass.
            if fileMeta[path] == item.meta { continue }
            guard let content = readFile(path) else { continue }
            let hash = Self.hash(content)
            if fingerprints[path] == hash {
                fileMeta[path] = item.meta  // mtime-only touch
                continue
            }
            snapshot.append(ParseSnapshot(path: path, content: content,
                                          hash: hash, meta: item.meta))
        }
        // Parse the rest on a background thread, in cancellable batches.
        let parsed = await Self.parseInBackground(snapshot)
        // Merge whatever completed — even when cancelled, partial progress
        // is valid and lets the next pass converge instead of restarting.
        var rebuilt = false
        for file in parsed {
            files[file.parsed.path] = file.parsed.entry
            fingerprints[file.parsed.path] = file.parsed.entry.hash
            fileMeta[file.parsed.path] = file.meta
            rebuilt = true
        }
        // Drop deleted files.
        let live = Set(ordered.map(\.path))
        for path in files.keys where !live.contains(path) {
            files.removeValue(forKey: path)
            fingerprints.removeValue(forKey: path)
            fileMeta.removeValue(forKey: path)
            rebuilt = true
        }
        if rebuilt { rebuildLookup() }
        indexedCount = live.count
        // 4.0.3 S9 (P0-G): background merge also bumps the generation.
        if rebuilt { generation += 1 }
    }

    /// Parse one file into the index. Files with syntax errors keep their
    /// previous (stale) entry so mid-typing doesn't nuke cross-file lookup.
    private func index(path: String, source: String, hash: UInt64) {
        guard let parsed = Self.parseFile(path: path, content: source) else { return }
        files[path] = parsed.entry
        fingerprints[path] = hash
    }

    private func rebuildLookup() {
        var views: [String: (file: String, view: PreviewViewStruct)] = [:]
        var tokens: [String: PreviewToken] = [:]
        var types: [String: PreviewTypeInfo] = [:]
        // 4.0.3 S1: track which files contributed each symbol so same-name
        // conflicts become an observable warning instead of a silent
        // last-writer-wins.
        var viewSources: [String: [String]] = [:]
        var typeSources: [String: [String]] = [:]
        for path in files.keys.sorted() {
            guard let entry = files[path] else { continue }
            let role = PreviewSourceRole.classify(path: path)
            for (name, view) in entry.views {
                // 4.0.3 S10 (P0-H): a production definition always wins
                // over a same-name generated/test/prototype one — a
                // generated fixture can never shadow (or become) a
                // production view.
                if let existing = views[name],
                   !Self.roleWins(newRole: role,
                                  over: PreviewSourceRole.classify(path: existing.file)) {
                    viewSources[name, default: []].append(path)
                    continue
                }
                views[name] = (path, view)
                viewSources[name, default: []].append(path)
            }
            for token in entry.tokens { tokens[token.qualifiedName] = token }
            for (name, info) in entry.types {
                if let existing = types[name],
                   !Self.roleWins(newRole: role,
                                  over: PreviewSourceRole.classify(path: existing.filePath)) {
                    typeSources[name, default: []].append(path)
                    continue
                }
                types[name] = info
                typeSources[name, default: []].append(path)
            }
        }
        viewsByName = views
        tokensByName = tokens
        typesByName = types

        // 4.0.3 S1: record conflicts (deterministic order for stable tests).
        // 4.0.3 S10: a production-vs-generated collision gets the specific
        // diagGeneratedShadowed instead of the generic conflict warning.
        var diags: [PreviewDiagnostic] = []
        for name in viewSources.keys.sorted() {
            let sources = viewSources[name] ?? []
            if sources.count > 1 {
                diags.append(Self.collisionDiagnostic(name: name, sources: sources))
            }
        }
        for name in typeSources.keys.sorted() {
            let sources = typeSources[name] ?? []
            if sources.count > 1 {
                diags.append(Self.collisionDiagnostic(name: name, sources: sources))
            }
        }
        indexDiagnostics = diags
    }

    /// 4.0.3 S10 (P0-H): production beats any non-production role;
    /// within the same role the later (sorted) path wins, preserving the
    /// pre-4.0.3 last-writer-wins behavior.
    private static func roleWins(newRole: PreviewSourceRole,
                                 over existingRole: PreviewSourceRole) -> Bool {
        if newRole == .production, existingRole != .production { return true }
        if existingRole == .production, newRole != .production { return false }
        return true
    }

    /// 4.0.3 S10: collision diagnostic — generated shadowed by production
    /// gets the specific key; same-role collisions keep the S1 warning.
    private static func collisionDiagnostic(name: String, sources: [String]) -> PreviewDiagnostic {
        let roles = Set(sources.map { PreviewSourceRole.classify(path: $0) })
        if roles.contains(.production), roles.count > 1 {
            let generated = sources.filter { PreviewSourceRole.classify(path: $0) != .production }
            return PreviewDiagnostic(
                severity: .warning, key: .diagGeneratedShadowed,
                params: [name, generated.joined(separator: ", ")],
                file: sources.first ?? "", line: nil, api: name)
        }
        return PreviewDiagnostic(
            severity: .warning, key: .diagIndexSymbolConflict,
            params: [name, sources.joined(separator: ", "), sources.last ?? ""],
            file: sources.first ?? "", line: nil, api: name)
    }

    // MARK: - Parsing (thread-safe: fresh parser per call, no shared state)

    /// One file's parse output. Produced on a background thread, merged on
    /// the caller's actor; the handoff is single-producer → single-consumer
    /// via `await`, so no shared mutation can occur.
    private struct ParsedFile: @unchecked Sendable {
        let path: String
        let entry: IndexedFile
    }

    /// One file's snapshot for background parsing (P1-11: carries the
    /// stat meta so the merge can record it only for parsed files).
    private struct ParseSnapshot: Sendable {
        let path: String
        let content: String
        let hash: UInt64
        let meta: FileMeta
    }

    /// Parses one file; nil when the file has syntax errors (caller keeps the
    /// stale entry).
    private static func parseFile(path: String, content: String) -> ParsedFile? {
        let engine = PreviewEngine(source: content)
        guard let (file, converter) = engine.parseTree() else { return nil }
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: file)
        let tokens = PreviewEngine.extractTokens(file: file, fileName: path,
                                                 converter: converter)
        var types: [String: PreviewTypeInfo] = [:]
        for info in PreviewEngine.extractTypes(file: file, filePath: path) {
            types[info.name] = info
        }
        return ParsedFile(path: path,
                          entry: IndexedFile(path: path,
                                             hash: hash(content),
                                             views: doc.views,
                                             tokens: tokens,
                                             types: types))
    }

    /// Parses snapshotted files on a background thread, in batches, checking
    /// cancellation between batches. Never touches the caller's actor or the
    /// index itself.
    ///
    /// 4.0.2 P1-11: cancellation is propagated into the detached task via
    /// `withTaskCancellationHandler` — a detached task does NOT inherit the
    /// caller's cancellation, so without this the batch check would be dead.
    private static func parseInBackground(
        _ snapshot: [ParseSnapshot]
    ) async -> [(parsed: ParsedFile, meta: FileMeta)] {
        guard !snapshot.isEmpty else { return [] }
        let parseTask = Task.detached(priority: .userInitiated) {
            () -> [(parsed: ParsedFile, meta: FileMeta)] in
            var out: [(parsed: ParsedFile, meta: FileMeta)] = []
            out.reserveCapacity(snapshot.count)
            for batchStart in stride(from: 0, to: snapshot.count,
                                     by: ProjectIndexPolicy.backgroundBatchSize) {
                if Task.isCancelled { break }
                let batchEnd = min(batchStart + ProjectIndexPolicy.backgroundBatchSize,
                                   snapshot.count)
                for i in batchStart..<batchEnd {
                    let file = snapshot[i]
                    if let parsed = parseFile(path: file.path, content: file.content) {
                        out.append((parsed, file.meta))
                    }
                }
            }
            return out
        }
        return await withTaskCancellationHandler {
            await parseTask.value
        } onCancel: {
            parseTask.cancel()
        }
    }

    // MARK: - Helpers

    /// Current file first; the rest keep path order (deterministic).
    private static func currentFileFirst(_ listed: [ListedFile],
                                         currentPath: String?) -> [ListedFile] {
        guard let currentPath,
              let idx = listed.firstIndex(where: { $0.path == currentPath }) else {
            return listed
        }
        var ordered = listed
        let current = ordered.remove(at: idx)
        ordered.insert(current, at: 0)
        return ordered
    }

    /// A Swift file found under the project root, with a cheap stat
    /// snapshot for the P1-11 mtime/size pre-filter.
    struct ListedFile {
        let path: String
        let url: URL
        let meta: FileMeta
    }

    private static func swiftFiles(under root: URL, projectName: String) -> [ListedFile] {
        var out: [ListedFile] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey,
                                      .contentModificationDateKey,
                                      .fileSizeKey]
        guard let enumerator = fm.enumerator(at: root,
                                            includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            var rel = url.path
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if rel.hasPrefix(prefix) { rel = String(rel.dropFirst(prefix.count)) }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let meta = FileMeta(mtime: values?.contentModificationDate ?? .distantPast,
                                size: values?.fileSize ?? -1)
            out.append(ListedFile(path: projectName + "/" + rel, url: url, meta: meta))
            if out.count >= ProjectIndexPolicy.maxFiles { break }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// FNV-1a over UTF-8 bytes — cheap content hash for change detection.
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return h
    }
}
