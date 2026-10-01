import Foundation

/// On-disk record of a GitHub-imported project (§9: repo metadata).
/// Stored as `.github-repo.json` inside the project folder (a dotfile, so
/// the navigator's `skipsHiddenFiles` scan hides it).
struct GitHubRepoMetadata: Codable, Equatable {
    static let fileName = ".github-repo.json"
    /// Hidden directory holding the pristine snapshot base (P0-2: patch
    /// export's `readBase`). Skipped by every `skipsHiddenFiles` scan.
    static let baseCopyName = ".codeberry-base"

    var owner: String
    var repo: String
    /// Branch / tag name, or "default". For commit imports, the short SHA.
    var refName: String
    var refKind: GitHubRefKind
    /// The immutable commit SHA the workspace currently mirrors.
    var baseSnapshotSHA: String
    var importedAt: Date
    var lastSyncAt: Date?
    /// Workspace-relative path → SHA-256 of file content at the last
    /// import/sync. The three-way merge compares base/local/remote against it.
    var manifest: [String: String]

    var slug: String { "\(owner)/\(repo)" }
    var shortSHA: String { String(baseSnapshotSHA.prefix(7)) }

    // MARK: - Persistence

    static func load(projectFolder: URL) -> GitHubRepoMetadata? {
        let url = projectFolder.appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GitHubRepoMetadata.self, from: data)
    }

    func save(projectFolder: URL) throws {
        let url = projectFolder.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Builds the manifest by hashing every non-hidden file under the folder.
    static func buildManifest(projectFolder: URL) -> [String: String] {
        var out: [String: String] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projectFolder,
                                            includingPropertiesForKeys: [.isRegularFileKey],
                                            options: [.skipsHiddenFiles]) else { return out }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = url.path.replacingOccurrences(of: projectFolder.standardized.path + "/", with: "")
            guard !rel.isEmpty, !rel.contains("..") else { continue }
            if let hash = try? ArchiveExtractor.sha256(of: url) {
                out[rel] = hash
            }
        }
        return out
    }
}

/// Recently imported repos, for the import sheet's quick-pick list.
/// Lightweight identifiers only — no tokens, no file contents.
struct GitHubRecentRepo: Codable, Equatable, Identifiable {
    let owner: String
    let repo: String
    let projectFolder: String
    let lastOpened: Date
    var id: String { "\(owner)/\(repo)" }
}

enum GitHubRecentStore {
    private static let key = "github.recentRepos"
    private static let maxCount = 10

    static func load() -> [GitHubRecentRepo] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([GitHubRecentRepo].self, from: data) else {
            return []
        }
        return list
    }

    static func record(owner: String, repo: String, projectFolder: String) {
        var list = load().filter { !($0.owner == owner && $0.repo == repo) }
        list.insert(GitHubRecentRepo(owner: owner, repo: repo,
                                     projectFolder: projectFolder, lastOpened: Date()),
                    at: 0)
        list = Array(list.prefix(maxCount))
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(projectFolder: String) {
        let list = load().filter { $0.projectFolder != projectFolder }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
