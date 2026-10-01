import Foundation

// MARK: - M4: Snapshot Mode — local changes & patch export
//
// Compares the working tree against the base snapshot manifest
// (recorded at import / last sync) to list local changes, and exports
// them as a unified diff patch.

/// A local modification relative to the base snapshot.
struct LocalChange: Equatable, Identifiable {
    enum Kind { case added, modified, deleted }
    let path: String
    let kind: Kind
    var id: String { path }
}

enum SnapshotChanges {
    /// Diffs two manifests (path → sha256) into a sorted change list.
    static func compute(base: [String: String], current: [String: String]) -> [LocalChange] {
        var out: [LocalChange] = []
        for (path, hash) in current {
            if let baseHash = base[path] {
                if baseHash != hash { out.append(.init(path: path, kind: .modified)) }
            } else {
                out.append(.init(path: path, kind: .added))
            }
        }
        for path in base.keys where current[path] == nil {
            out.append(.init(path: path, kind: .deleted))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Exports text-file changes as a unified diff. Binary/large files are
    /// listed in a header comment instead of diffed.
    static func unifiedDiff(changes: [LocalChange],
                            readFile: (String) -> String?,
                            readBase: (String) -> String?) -> String {
        var out: [String] = []
        out.append("# CodeBerry local-changes patch")
        out.append("# generated \(ISO8601DateFormatter().string(from: Date()))")
        for change in changes {
            out.append("--- a/\(change.path)")
            out.append("+++ b/\(change.path)")
            switch change.kind {
            case .deleted:
                out.append("@@ deleted @@")
                if let old = readBase(change.path) {
                    for line in old.components(separatedBy: "\n") { out.append("-\(line)") }
                }
            case .added:
                out.append("@@ added @@")
                if let new = readFile(change.path) {
                    for line in new.components(separatedBy: "\n") { out.append("+\(line)") }
                }
            case .modified:
                let oldLines = (readBase(change.path) ?? "").components(separatedBy: "\n")
                let newLines = (readFile(change.path) ?? "").components(separatedBy: "\n")
                out.append("@@ modified @@")
                for line in unifiedLineDiff(old: oldLines, new: newLines) { out.append(line) }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Simple LCS-based line diff (fine for patch export sizes).
    static func unifiedLineDiff(old: [String], new: [String]) -> [String] {
        let m = old.count, n = new.count
        // Cap the DP table to keep export bounded.
        guard m * n <= 250_000 else {
            return ["# (file too large for line diff — \(m) vs \(n) lines)"]
        }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                dp[i][j] = old[i] == new[j] ? dp[i+1][j+1] + 1 : max(dp[i+1][j], dp[i][j+1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < m && j < n {
            if old[i] == new[j] { out.append(" " + old[i]); i += 1; j += 1 }
            else if dp[i+1][j] >= dp[i][j+1] { out.append("-" + old[i]); i += 1 }
            else { out.append("+" + new[j]); j += 1 }
        }
        while i < m { out.append("-" + old[i]); i += 1 }
        while j < n { out.append("+" + new[j]); j += 1 }
        return out
    }
}
