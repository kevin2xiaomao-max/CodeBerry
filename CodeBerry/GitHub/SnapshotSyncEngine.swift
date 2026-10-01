import Foundation

/// A single file change the sync wants to apply.
struct GitHubSyncChange: Equatable {
    enum Kind { case added, modified, deleted }
    let path: String
    let kind: Kind
}

/// A file where local edits and remote changes collide (§9: 冲突未解决
/// 绝不覆盖本地 — conflicted files are never auto-overwritten).
struct GitHubSyncConflict: Equatable {
    enum Reason {
        /// Both sides changed the file differently since the base snapshot.
        case bothModified
        /// Deleted remotely, modified locally (or vice versa).
        case deleteVsModify
    }
    let path: String
    let reason: Reason
}

/// The result of comparing base / local / remote manifests.
struct GitHubSyncPlan: Equatable {
    /// Safe to apply automatically.
    let changes: [GitHubSyncChange]
    /// Require user resolution (M4 Conflict UI); never auto-applied.
    let conflicts: [GitHubSyncConflict]
    /// The remote SHA this plan was computed against.
    let remoteSHA: String

    var isEmpty: Bool { changes.isEmpty && conflicts.isEmpty }
}

/// Snapshot import + sync (§8/§9). Mode A only: there is no git here —
/// the UI calls it "同步 GitHub", never pull/stage/commit.
///
/// An actor so the engine itself is Sendable: the UI drives it from
/// @MainActor and progress callbacks are @Sendable + MainActor-hopped.
actor SnapshotSyncEngine {
    private let client: GitHubClient
    private let downloader: SnapshotDownloader
    private let fm = FileManager.default

    init(client: GitHubClient, downloader: SnapshotDownloader = SnapshotDownloader()) {
        self.client = client
        self.downloader = downloader
    }

    // MARK: - Import

    /// Downloads the snapshot for `resolved`, extracts it into a fresh
    /// project folder under `workspaceRoot`, and writes the metadata +
    /// manifest. Returns the project folder name.
    func importRepo(parsed: GitHubRepoRef, resolved: GitHubResolvedRef,
                    workspaceRoot: URL,
                    progress: @escaping @Sendable (ImportPhase) -> Void) async throws -> String {
        await MainActor.run { progress(.downloading(0)) }
        hookDownloadState { p in Task { @MainActor in progress(.downloading(p)) } }
        let zipURL = try await downloader.download(
            from: client.snapshotURL(owner: parsed.owner, repo: parsed.repo, sha: resolved.sha),
            auth: client.auth)
        defer { try? fm.removeItem(at: zipURL) }

        await MainActor.run { progress(.extracting) }
        let folderName = uniqueFolderName(for: parsed.repo, in: workspaceRoot)
        let projectFolder = workspaceRoot.appendingPathComponent(folderName)
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        _ = try ArchiveExtractor.extractSecurely(zipURL: zipURL, to: projectFolder) { _ in
            Task { @MainActor in progress(.extracting) }
        }

        let metadata = GitHubRepoMetadata(
            owner: parsed.owner, repo: parsed.repo,
            refName: resolved.name, refKind: resolved.kind,
            baseSnapshotSHA: resolved.sha,
            importedAt: Date(), lastSyncAt: nil,
            manifest: GitHubRepoMetadata.buildManifest(projectFolder: projectFolder))
        try metadata.save(projectFolder: projectFolder)
        // P0-2: pristine base copy for patch export's readBase. Hidden dir,
        // so manifests and the navigator (skipsHiddenFiles) ignore it.
        try Self.installBaseCopy(projectFolder: projectFolder)
        GitHubRecentStore.record(owner: parsed.owner, repo: parsed.repo, projectFolder: folderName)
        await MainActor.run { progress(.done) }
        return folderName
    }

    enum ImportPhase: Equatable {
        case downloading(Double)   // -1 = unknown size
        case extracting
        case done
    }

    // MARK: - Sync

    /// Computes what a sync would change, without touching the workspace.
    /// The remote HEAD is resolved first; when it equals `baseSnapshotSHA`
    /// the plan is trivially empty (no download at all).
    ///
    /// Returns the plan, the staging directory holding the extracted
    /// remote snapshot, and the remote manifest. The caller must pass
    /// `staging` to `apply(plan:…)` and then call `discardStaging(_:)` —
    /// or `discardStaging(_:)` directly when the user cancels.
    func planSync(projectFolder: URL, metadata: GitHubRepoMetadata,
                  progress: @escaping @Sendable (SyncPhase) -> Void) async throws
        -> (plan: GitHubSyncPlan, staging: URL?, remoteManifest: [String: String]) {
        await MainActor.run { progress(.resolving) }
        let remoteSHA = try await resolveRemoteSHA(for: metadata)
        guard remoteSHA != metadata.baseSnapshotSHA else {
            await MainActor.run { progress(.done) }
            return (GitHubSyncPlan(changes: [], conflicts: [], remoteSHA: remoteSHA), nil, [:])
        }
        await MainActor.run { progress(.resolving) }
        let remoteSHA = try await resolveRemoteSHA(for: metadata)
        guard remoteSHA != metadata.baseSnapshotSHA else {
            await MainActor.run { progress(.done) }
            return (GitHubSyncPlan(changes: [], conflicts: [], remoteSHA: remoteSHA), nil)
        }

        await MainActor.run { progress(.downloading(-1)) }
        hookDownloadState { p in Task { @MainActor in progress(.downloading(p)) } }
        let zipURL = try await downloader.download(
            from: client.snapshotURL(owner: metadata.owner, repo: metadata.repo, sha: remoteSHA),
            auth: client.auth)
        defer { try? fm.removeItem(at: zipURL) }

        await MainActor.run { progress(.comparing) }
        let staging = fm.temporaryDirectory.appendingPathComponent("codeberry-sync-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = try ArchiveExtractor.extractSecurely(zipURL: zipURL, to: staging)
        let remoteManifest = GitHubRepoMetadata.buildManifest(projectFolder: staging)

        let localManifest = GitHubRepoMetadata.buildManifest(projectFolder: projectFolder)
        let plan = Self.threeWayDiff(base: metadata.manifest, local: localManifest,
                                     remote: remoteManifest, remoteSHA: remoteSHA)
        await MainActor.run { progress(.done) }
        return (plan, staging, remoteManifest)
    }

    nonisolated func discardStaging(_ staging: URL?) {
        guard let staging else { return }
        try? FileManager.default.removeItem(at: staging)
    }

    /// Applies the non-conflicting changes of a plan. Conflicted files are
    /// left untouched (§9). Updates the manifest + metadata on success.
    /// `staging` is the directory returned by `planSync` (nil when the plan
    /// is empty — nothing to apply).
    ///
    /// P1-2 (partial sync): when `plan.conflicts` is non-empty the workspace
    /// is NOT cleanly at `remoteSHA`, so `baseSnapshotSHA` must NOT advance
    /// and conflicted files keep their OLD base hashes. Only cleanly applied
    /// paths advance to the remote hashes — the next three-way diff still
    /// detects the divergence correctly and local content is never silently
    /// promoted into a "clean" base. Paths untouched by the plan (e.g.
    /// non-conflicting local edits) also keep their old base hashes, so they
    /// stay visible as local changes instead of being baked into the base.
    /// nonisolated: touches only the immutable `fm` and static helpers.
    nonisolated func apply(plan: GitHubSyncPlan, staging: URL?,
                           metadata: GitHubRepoMetadata,
                           projectFolder: URL) throws -> GitHubRepoMetadata {
        if let staging {
            let fm = FileManager.default
            for change in plan.changes {
                let localURL = projectFolder.appendingPathComponent(change.path)
                let remoteURL = staging.appendingPathComponent(change.path)
                switch change.kind {
                case .added, .modified:
                    try fm.createDirectory(at: localURL.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    if fm.fileExists(atPath: localURL.path) { try fm.removeItem(at: localURL) }
                    try fm.copyItem(at: remoteURL, to: localURL)
                case .deleted:
                    if fm.fileExists(atPath: localURL.path) { try fm.removeItem(at: localURL) }
                }
            }
        }
        var updated = metadata
        updated.lastSyncAt = Date()
        if plan.conflicts.isEmpty {
            // Clean sync: the workspace now mirrors remoteSHA exactly.
            updated.baseSnapshotSHA = plan.remoteSHA
        }
        // Advance the base ONLY for cleanly applied paths. On a clean sync
        // applying every change to the old base yields exactly the remote
        // tree, so this equals the old rebuild-from-workspace behavior for
        // untouched workspaces — but it no longer bakes unrelated local
        // edits into the base.
        var base = metadata.manifest
        if let staging {
            let remoteManifest = GitHubRepoMetadata.buildManifest(projectFolder: staging)
            for change in plan.changes {
                if let hash = remoteManifest[change.path] {
                    base[change.path] = hash
                } else {
                    base.removeValue(forKey: change.path)
                }
            }
            try Self.refreshBaseCopy(projectFolder: projectFolder, staging: staging,
                                     appliedChanges: plan.changes,
                                     fullRefresh: plan.conflicts.isEmpty)
        }
        updated.manifest = base
        try updated.save(projectFolder: projectFolder)
        return updated
    }

    // MARK: - P0-2: pristine base copy

    /// Copies a tree into the hidden `.codeberry-base/` directory — the
    /// pristine snapshot base used by patch export's `readBase`. Hidden, so
    /// manifests and the navigator (`skipsHiddenFiles`) ignore it.
    nonisolated static func installBaseCopy(projectFolder: URL) throws {
        try replaceBaseCopy(projectFolder: projectFolder, from: projectFolder)
    }

    /// Keeps `.codeberry-base/` consistent with the base manifest after apply:
    /// full refresh on clean sync (base == staging tree), per-change update on
    /// partial sync. A missing base copy (pre-4.0.1 imports) is rebuilt fully.
    nonisolated static func refreshBaseCopy(projectFolder: URL, staging: URL,
                                            appliedChanges: [GitHubSyncChange],
                                            fullRefresh: Bool) throws {
        if fullRefresh || !FileManager.default.fileExists(
            atPath: projectFolder.appendingPathComponent(GitHubRepoMetadata.baseCopyName).path) {
            try replaceBaseCopy(projectFolder: projectFolder, from: staging)
            return
        }
        let fm = FileManager.default
        let baseCopy = projectFolder.appendingPathComponent(GitHubRepoMetadata.baseCopyName)
        for change in appliedChanges {
            let baseURL = baseCopy.appendingPathComponent(change.path)
            let remoteURL = staging.appendingPathComponent(change.path)
            switch change.kind {
            case .added, .modified:
                try fm.createDirectory(at: baseURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                if fm.fileExists(atPath: baseURL.path) { try fm.removeItem(at: baseURL) }
                try fm.copyItem(at: remoteURL, to: baseURL)
            case .deleted:
                if fm.fileExists(atPath: baseURL.path) { try fm.removeItem(at: baseURL) }
            }
        }
    }

    nonisolated private static func replaceBaseCopy(projectFolder: URL, from source: URL) throws {
        let fm = FileManager.default
        let baseCopy = projectFolder.appendingPathComponent(GitHubRepoMetadata.baseCopyName)
        if fm.fileExists(atPath: baseCopy.path) { try fm.removeItem(at: baseCopy) }
        try fm.createDirectory(at: baseCopy, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles])
        for item in items where item.lastPathComponent != GitHubRepoMetadata.baseCopyName {
            try fm.copyItem(at: item, to: baseCopy.appendingPathComponent(item.lastPathComponent))
        }
    }

    enum SyncPhase: Equatable {
        case resolving
        case downloading(Double)
        case comparing
        case done
    }

    // MARK: - Private

    private func resolveRemoteSHA(for metadata: GitHubRepoMetadata) async throws -> String {
        switch metadata.refKind {
        case .defaultBranch:
            let info = try await client.repoInfo(owner: metadata.owner, repo: metadata.repo)
            return try await client.branchHead(owner: metadata.owner, repo: metadata.repo,
                                               branch: info.defaultBranch)
        case .branch:
            return try await client.branchHead(owner: metadata.owner, repo: metadata.repo,
                                               branch: metadata.refName)
        case .tag:
            if let sha = try await client.tagCommitSHA(owner: metadata.owner, repo: metadata.repo,
                                                       tag: metadata.refName) { return sha }
            throw GitHubError.notFound(owner: metadata.owner, repo: "\(metadata.repo)@\(metadata.refName)")
        case .commit:
            // Pinned to a commit: there is nothing newer to sync to.
            return metadata.baseSnapshotSHA
        }
    }

    private func hookDownloadState(_ handler: @escaping @Sendable (Double) -> Void) {
        // `downloader` is @unchecked Sendable; `self` must not cross into the Task.
        let downloader = self.downloader
        Task { @MainActor in
            downloader.onStateChange = { state in
                if case .downloading(let p) = state { handler(p) }
            }
        }
    }

    private func uniqueFolderName(for repo: String, in root: URL) -> String {
        // Sanitize: keep it a safe single path component.
        var base = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.replacingOccurrences(of: "/", with: "-")
        if base.isEmpty { base = "GitHubRepo" }
        var candidate = base
        var i = 2
        while fm.fileExists(atPath: root.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(i)"
            i += 1
        }
        return candidate
    }

    // MARK: - Three-way diff

    /// Pure function — unit-tested directly (`WorkspaceSyncTests`).
    /// - base: manifest at last import/sync
    /// - local: current workspace files
    /// - remote: freshly downloaded snapshot
    static func threeWayDiff(base: [String: String], local: [String: String],
                             remote: [String: String], remoteSHA: String) -> GitHubSyncPlan {
        var changes: [GitHubSyncChange] = []
        var conflicts: [GitHubSyncConflict] = []
        let paths = Set(base.keys).union(local.keys).union(remote.keys)
        for path in paths.sorted() {
            let b = base[path], l = local[path], r = remote[path]
            if l == r { continue }                       // identical (incl. both deleted)
            if l == b {
                // Local untouched → take remote.
                if r == nil { changes.append(.init(path: path, kind: .deleted)) }
                else if b == nil { changes.append(.init(path: path, kind: .added)) }
                else { changes.append(.init(path: path, kind: .modified)) }
            } else if r == b {
                continue                                  // remote untouched → keep local
            } else {
                // Both sides diverged from base.
                if (l == nil) != (r == nil) {
                    conflicts.append(.init(path: path, reason: .deleteVsModify))
                } else {
                    conflicts.append(.init(path: path, reason: .bothModified))
                }
            }
        }
        return GitHubSyncPlan(changes: changes, conflicts: conflicts, remoteSHA: remoteSHA)
    }
}
