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

/// §二 Multi-file preview: a project-wide index of View structs and design
/// tokens. Incremental — each file is fingerprinted, only changed files are
/// re-parsed. Capped at `maxFiles` so huge projects can't stall the canvas.
@Observable
final class PreviewProjectIndex {
    static let maxFiles = 100

    struct IndexedFile {
        let path: String
        let hash: UInt64
        let views: [String: PreviewViewStruct]
        let tokens: [PreviewToken]
    }

    private var files: [String: IndexedFile] = [:]
    private var fingerprints: [String: String] = [:]

    /// All Views in the project: name → (defining file, struct).
    private(set) var viewsByName: [String: (file: String, view: PreviewViewStruct)] = [:]
    /// All design tokens: qualified name → token.
    private(set) var tokensByName: [String: PreviewToken] = [:]

    /// Progress UI (§二: "正在建立预览索引").
    var isIndexing = false
    var indexedCount = 0
    var totalCount = 0

    /// Incremental update.
    /// - `projectRoot`: the opened project's folder URL.
    /// - `projectName`: top-level folder name (paths are `"<project>/<rel>"`).
    /// - `currentPath`/`currentSource`: the file being edited — its editor
    ///   buffer wins over disk ("当前文件的定义优先").
    /// - `readFile`: reads any other workspace-relative path from disk.
    func update(projectRoot: URL,
                projectName: String,
                currentPath: String?,
                currentSource: String?,
                readFile: (String) -> String?) {
        let entries = Self.swiftFiles(under: projectRoot, projectName: projectName)
        totalCount = entries.count
        var rebuilt = false

        for (path, url) in entries {
            if path == currentPath, let src = currentSource {
                let h = Self.hash(src)
                if files[path]?.hash != h {
                    index(path: path, source: src)
                    rebuilt = true
                }
                fingerprints[path] = "editor"
                continue
            }
            // Cheap change detection: mtime + size. Contents are only read
            // when the fingerprint changed.
            let fp = Self.fingerprint(of: url) ?? UUID().uuidString
            if fingerprints[path] == fp, files[path] != nil { continue }
            fingerprints[path] = fp
            guard let src = readFile(path) else {
                if files.removeValue(forKey: path) != nil { rebuilt = true }
                continue
            }
            let h = Self.hash(src)
            if files[path]?.hash == h { continue }
            index(path: path, source: src)
            rebuilt = true
        }

        // Drop deleted files.
        let live = Set(entries.map(\.path))
        for path in files.keys where !live.contains(path) {
            files.removeValue(forKey: path)
            rebuilt = true
        }

        if rebuilt { rebuildLookup() }
        indexedCount = totalCount
    }

    /// Parse one file into the index. Files with syntax errors keep their
    /// previous (stale) entry so mid-typing doesn't nuke cross-file lookup.
    private func index(path: String, source: String) {
        guard let (file, converter) = PreviewEngine(source: source).parseTree() else { return }
        var doc = PreviewDocument()
        PreviewEngine.collect(into: &doc, from: file)
        let tokens = PreviewEngine.extractTokens(file: file, fileName: path, converter: converter)
        files[path] = IndexedFile(path: path,
                                  hash: Self.hash(source),
                                  views: doc.views,
                                  tokens: tokens)
    }

    private func rebuildLookup() {
        var views: [String: (file: String, view: PreviewViewStruct)] = [:]
        var tokens: [String: PreviewToken] = [:]
        for path in files.keys.sorted() {
            guard let entry = files[path] else { continue }
            for (name, view) in entry.views { views[name] = (path, view) }
            for token in entry.tokens { tokens[token.qualifiedName] = token }
        }
        viewsByName = views
        tokensByName = tokens
    }

    // MARK: - Helpers

    private static func swiftFiles(under root: URL, projectName: String) -> [(path: String, url: URL)] {
        var out: [(path: String, url: URL)] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                            includingPropertiesForKeys: [.isRegularFileKey],
                                            options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            var rel = url.path
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if rel.hasPrefix(prefix) { rel = String(rel.dropFirst(prefix.count)) }
            out.append((path: projectName + "/" + rel, url: url))
            if out.count >= maxFiles { break }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func fingerprint(of url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? NSNumber else { return nil }
        return "\(mtime.timeIntervalSince1970)-\(size.intValue)"
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
