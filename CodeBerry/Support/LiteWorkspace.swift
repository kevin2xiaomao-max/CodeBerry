import Foundation

/// Minimal local replacement for AgentKit's `Workspace` file helper,
/// scoped to the app's workspace root. Lite build only: plain
/// FileManager-backed read/write/resolve, no agent tooling.
struct LiteWorkspace {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// Resolves a workspace-relative path, refusing to escape the root.
    func resolve(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardized
        let rootPath = root.standardized.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return url
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: resolve(path), encoding: .utf8)
    }

    func write(_ path: String, content: String) throws {
        let url = try resolve(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
