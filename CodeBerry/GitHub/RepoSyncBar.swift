import SwiftUI

/// Sync view model for one GitHub-backed project (§9).
@Observable
@MainActor
final class RepoSyncModel {
    var metadata: GitHubRepoMetadata?
    var syncPhase: SnapshotSyncEngine.SyncPhase?
    var lastResult: String?
    var lastError: String?
    var conflictCount = 0

    private var engine: SnapshotSyncEngine?
    private var downloader = SnapshotDownloader()

    var isSyncing: Bool { syncPhase != nil }

    func refresh(projectFolder: URL) {
        metadata = GitHubRepoMetadata.load(projectFolder: projectFolder)
        if engine == nil {
            let client = GitHubClient(auth: GitHubTokenStore.currentAuth())
            engine = SnapshotSyncEngine(client: client, downloader: downloader)
        }
    }

    func cancel() { downloader.cancel() }

    /// Plans and applies a sync. Conflicted files are left untouched and
    /// reported (§9: 冲突未解决绝不覆盖本地).
    func sync(projectFolder: URL) async {
        guard let metadata, let engine, !isSyncing else { return }
        lastResult = nil
        lastError = nil
        conflictCount = 0
        syncPhase = .resolving
        do {
            let (plan, staging, _) = try await engine.planSync(projectFolder: projectFolder,
                                                            metadata: metadata) { [weak self] phase in
                Task { @MainActor in self?.syncPhase = phase }
            }
            defer { engine.discardStaging(staging) }
            if plan.isEmpty {
                // Still refresh the metadata timestamps.
                var updated = metadata
                updated.lastSyncAt = Date()
                try? updated.save(projectFolder: projectFolder)
                self.metadata = updated
                lastResult = L10nService.shared.t(.githubSyncedUpToDate)
            } else {
                let updated = try engine.apply(plan: plan, staging: staging,
                                               metadata: metadata, projectFolder: projectFolder)
                self.metadata = updated
                conflictCount = plan.conflicts.count
                var parts: [String] = []
                if !plan.changes.isEmpty {
                    parts.append(L10nService.shared.t(.githubSyncApplied, plan.changes.count))
                }
                if !plan.conflicts.isEmpty {
                    parts.append(L10nService.shared.t(.githubSyncConflicts, plan.conflicts.count))
                }
                lastResult = parts.joined(separator: "；")
            }
        } catch {
            if let gh = error as? GitHubError {
                lastError = gh.errorDescription
            } else if let ex = error as? ArchiveExtractor.ExtractError {
                lastError = ex.errorDescription
            } else {
                lastError = error.localizedDescription
            }
        }
        syncPhase = nil
    }
}

/// Compact repo header shown above the file tree for GitHub-backed projects:
/// `owner/repo @ branch (a1b2c3d)` + Sync button + status.
struct RepoSyncBar: View {
    @Bindable var store: WorkspaceStore
    @State private var model = RepoSyncModel()
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        if let metadata = model.metadata, let folder = projectFolder {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metadata.slug)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("\(metadata.refName) · \(metadata.shortSHA)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if model.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(l10n.t(.githubSyncAction)) {
                            Task { await model.sync(projectFolder: folder) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if model.isSyncing, case .downloading(let p) = model.syncPhase, p >= 0 {
                    ProgressView(value: p)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
                if let result = model.lastResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(model.conflictCount > 0 ? .orange : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
            }
            .background(.bar)
            .task(id: store.currentProject) {
                if let folder = projectFolder { model.refresh(projectFolder: folder) }
            }
            .onChange(of: store.currentProject) { _, _ in
                model.lastResult = nil
                model.lastError = nil
                if let folder = projectFolder { model.refresh(projectFolder: folder) }
            }
        }
    }

    private var projectFolder: URL? {
        guard let name = store.currentProject else { return nil }
        return store.rootURL.appendingPathComponent(name)
    }
}
