import Foundation

// MARK: - M4.1: GitHub sync orchestration (P0-2)
//
// Wires the Changes tab to the real SnapshotSyncEngine: real local changes
// from the manifest, real plan → apply, and real conflict resolution
// (Keep Local / Use Remote / Manual Merge) against the retained staging
// snapshot. Conflict semantics follow P1-2: unresolved conflicts never
// advance the base.

/// Errors from the sync orchestration layer.
enum WorkspaceSyncError: LocalizedError {
    case notGitHubProject

    var errorDescription: String? {
        switch self {
        case .notGitHubProject: return L10nService.shared.t(.githubNotAProject)
        }
    }
}

extension WorkspaceStore {

    private func makeSyncEngine() -> SnapshotSyncEngine {
        if let syncEngine { return syncEngine }
        let engine = SnapshotSyncEngine(client: GitHubClient(auth: GitHubTokenStore.currentAuth()),
                                        downloader: syncDownloader)
        syncEngine = engine
        return engine
    }

    /// Reloads GitHub state for the open project. Called by
    /// openProject/closeProject and on session restore; drops any pending
    /// sync and the in-memory conflict list.
    func refreshGitHubState() {
        discardPendingSync()
        syncConflicts = []
        syncError = nil
        syncNotice = nil
        guard let root = previewProjectRoot() else { githubMetadata = nil; return }
        githubMetadata = GitHubRepoMetadata.load(projectFolder: root)
    }

    /// Real local changes vs the snapshot base: added / modified / deleted.
    func computeLocalChanges() -> [LocalChange] {
        guard let root = previewProjectRoot(),
              let metadata = githubMetadata else { return [] }
        let current = GitHubRepoMetadata.buildManifest(projectFolder: root)
        return SnapshotChanges.compute(base: metadata.manifest, current: current)
    }

    /// Pristine base content for patch export. Nil when the base copy is
    /// missing (pre-4.0.1 imports) or the file isn't UTF-8 text.
    func baseFileContent(relativePath path: String) -> String? {
        guard let root = previewProjectRoot() else { return nil }
        let baseCopy = root.appendingPathComponent(GitHubRepoMetadata.baseCopyName)
        let url = baseCopy.appendingPathComponent(path)
        guard Self.isWithinRoot(baseCopy, url: url) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Plans a sync against the real remote, retaining the staging snapshot
    /// and remote manifest for apply / conflict resolution. Throws for
    /// non-GitHub projects (the UI disables sync there; this is defensive).
    func planGitHubSync(progress: @escaping @Sendable (SnapshotSyncEngine.SyncPhase) -> Void = { _ in }) async throws -> GitHubSyncPlan {
        let engine = makeSyncEngine()
        guard let root = previewProjectRoot(), let metadata = githubMetadata else {
            throw WorkspaceSyncError.notGitHubProject
        }
        isSyncing = true
        defer { isSyncing = false }
        let (plan, staging, remoteManifest) = try await engine.planSync(
            projectFolder: root, metadata: metadata, progress: progress)
        discardPendingSync()
        if !plan.isEmpty {
            pendingSyncPlan = plan
            pendingSyncStaging = staging
            pendingRemoteManifest = remoteManifest
        }
        return plan
    }

    /// Applies the pending plan (P1-2 partial-base semantics live in
    /// `SnapshotSyncEngine.apply`). Refreshes tree / editor / index after.
    func applyPendingSync() throws {
        let engine = makeSyncEngine()
        guard let root = previewProjectRoot(),
              let metadata = githubMetadata,
              let plan = pendingSyncPlan else { return }
        let updated = try engine.apply(plan: plan, staging: pendingSyncStaging,
                                       metadata: metadata, projectFolder: root)
        githubMetadata = updated
        syncConflicts = plan.conflicts
        pendingSyncPlan = nil
        if syncConflicts.isEmpty { discardPendingSync() }
        // Files on disk changed: refresh the tree, the open editor buffer,
        // and the symbol / preview indexes.
        handleAgentMutation()
        rebuildSymbolIndex()
        analyzeProject()
    }

    /// Drops the retained staging snapshot (user cancelled, project closed,
    /// or all conflicts resolved).
    func discardPendingSync() {
        if let staging = pendingSyncStaging { makeSyncEngine().discardStaging(staging) }
        pendingSyncStaging = nil
        pendingSyncPlan = nil
        pendingRemoteManifest = [:]
    }

    /// "Keep Local": local content wins. The path's base becomes the REMOTE
    /// hash seen at plan time, so the next three-way diff stays quiet while
    /// remote is unchanged and re-detects the divergence when remote moves
    /// again (P1-2). The pristine base copy follows the manifest.
    func resolveConflictKeepLocal(_ conflict: GitHubSyncConflict) async throws {
        try await ensurePendingSync()
        guard var metadata = githubMetadata,
              let root = previewProjectRoot(),
              let staging = pendingSyncStaging else { return }
        if let remoteHash = pendingRemoteManifest[conflict.path] {
            metadata.manifest[conflict.path] = remoteHash
        } else {
            metadata.manifest.removeValue(forKey: conflict.path)
        }
        let remoteExists = FileManager.default.fileExists(
            atPath: staging.appendingPathComponent(conflict.path).path)
        try SnapshotSyncEngine.refreshBaseCopy(
            projectFolder: root, staging: staging,
            appliedChanges: [GitHubSyncChange(path: conflict.path,
                                              kind: remoteExists ? .modified : .deleted)],
            fullRefresh: false)
        try metadata.save(projectFolder: root)
        githubMetadata = metadata
        syncConflicts.removeAll { $0.path == conflict.path }
        if syncConflicts.isEmpty { discardPendingSync() }
    }

    /// "Use Remote": remote content wins — overwrites the local file from the
    /// retained staging snapshot. Base (manifest + pristine copy) becomes
    /// the remote state.
    func resolveConflictUseRemote(_ conflict: GitHubSyncConflict) async throws {
        try await ensurePendingSync()
        guard var metadata = githubMetadata,
              let root = previewProjectRoot(),
              let staging = pendingSyncStaging else { return }
        let fm = FileManager.default
        let localURL = root.appendingPathComponent(conflict.path)
        let remoteURL = staging.appendingPathComponent(conflict.path)
        guard Self.isWithinRoot(root, url: localURL),
              Self.isWithinRoot(staging, url: remoteURL) else { return }
        if fm.fileExists(atPath: remoteURL.path) {
            try fm.createDirectory(at: localURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: localURL.path) { try fm.removeItem(at: localURL) }
            try fm.copyItem(at: remoteURL, to: localURL)
            if let remoteHash = pendingRemoteManifest[conflict.path] {
                metadata.manifest[conflict.path] = remoteHash
            }
        } else {
            // Remote deleted the file: "use remote" deletes it locally.
            if fm.fileExists(atPath: localURL.path) { try fm.removeItem(at: localURL) }
            metadata.manifest.removeValue(forKey: conflict.path)
        }
        let remoteExists = fm.fileExists(atPath: remoteURL.path)
        try SnapshotSyncEngine.refreshBaseCopy(
            projectFolder: root, staging: staging,
            appliedChanges: [GitHubSyncChange(path: conflict.path,
                                              kind: remoteExists ? .modified : .deleted)],
            fullRefresh: false)
        try metadata.save(projectFolder: root)
        githubMetadata = metadata
        syncConflicts.removeAll { $0.path == conflict.path }
        handleAgentMutation()
        rebuildSymbolIndex()
        if syncConflicts.isEmpty { discardPendingSync() }
    }

    /// Test seam: injects a pending sync without hitting the network.
    /// The production flow always goes through `planGitHubSync`.
    func injectPendingSyncForTesting(plan: GitHubSyncPlan, staging: URL?,
                                     remoteManifest: [String: String]) {
        pendingSyncPlan = plan
        pendingSyncStaging = staging
        pendingRemoteManifest = remoteManifest
    }

    // MARK: - Private

    private func ensurePendingSync() async throws {
        if pendingSyncStaging != nil { return }
        _ = try await planGitHubSync()
    }

    private static func isWithinRoot(_ root: URL, url: URL) -> Bool {
        let base = root.standardized.path
        let target = url.standardized.path
        return target == base || target.hasPrefix(base + "/")
    }
}
