import Foundation

// MARK: - 4.0.3 S11 (P0-I): unified project file policy
//
// The single file policy shared by the Analyzer, the ProjectIndex, and
// Page Discovery. Before 4.0.3 the three disagreed: the Analyzer skipped
// `Pods`/`DerivedData`/`node_modules`/… while the index enumerated them
// (its enumerator only skipped dot-dirs). Now all three go through this
// policy, so they always agree on the file set:
//
// - maxFiles: cap on Swift files per project.
// - excludedDirNames: directories never descended into.
// - sourceRoots: project-relative roots to consider (empty = whole project).
// - role classification: delegated to `PreviewSourceRole` (S10).

/// One Swift file found by the policy enumeration.
struct PolicyListedFile: Sendable {
    /// Root-relative path, e.g. "Features/Home/HomeView.swift".
    let rel: String
    let url: URL
    let mtime: Date
    let size: Int
}

struct PreviewProjectFilePolicy: Sendable {
    var maxFiles: Int
    var excludedDirNames: Set<String>
    var sourceRoots: [String]

    static let `default` = PreviewProjectFilePolicy()

    init(maxFiles: Int = ProjectIndexPolicy.maxFiles,
         excludedDirNames: Set<String> = [
            ".git", ".build", "Pods", "DerivedData", ".swiftpm",
            "Carthage", "node_modules", "fastlane",
         ],
         sourceRoots: [String] = []) {
        self.maxFiles = maxFiles
        self.excludedDirNames = excludedDirNames
        self.sourceRoots = sourceRoots
    }

    /// Role classification for a project-relative path (S10).
    func role(path: String, content: String? = nil) -> PreviewSourceRole {
        PreviewSourceRole.classify(path: path, content: content)
    }

    /// Enumerate Swift files under `root`, applying exclusions, source
    /// roots, and the cap. Also detects the project kind in the same pass.
    /// Sorted by rel path for deterministic results.
    func swiftFiles(under root: URL,
                    isCancelled: @escaping @Sendable () -> Bool = { false })
    -> (files: [PolicyListedFile], kind: ProjectKind) {
        var out: [PolicyListedFile] = []
        var kind: ProjectKind = .unknown
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey,
                                      .contentModificationDateKey, .fileSizeKey]
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles]) else {
            return ([], .unknown)
        }
        for case let url as URL in enumerator {
            if isCancelled() { break }
            let name = url.lastPathComponent
            if excludedDirNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcodeproj" { kind = .xcodeproj }
            else if url.pathExtension == "xcworkspace" { kind = .xcworkspace }
            else if name == "Package.swift" && kind == .unknown { kind = .packageSwift }
            guard url.pathExtension == "swift" else { continue }
            var rel = url.path
            if rel.hasPrefix(prefix) { rel = String(rel.dropFirst(prefix.count)) }
            if !sourceRoots.isEmpty,
               !sourceRoots.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            out.append(PolicyListedFile(
                rel: rel,
                url: url,
                mtime: values?.contentModificationDate ?? .distantPast,
                size: values?.fileSize ?? -1))
            if out.count >= maxFiles { break }
        }
        out.sort { $0.rel < $1.rel }
        return (out, kind)
    }
}
