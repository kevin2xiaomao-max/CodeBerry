import SwiftUI

// MARK: - M4 Views: Conflict UI, Local History, Changes tab, Offline banner

// MARK: - SyncConflictView
//
// Lists GitHubSyncConflicts with per-file resolution: keep local,
// use remote, or open in editor for manual merge.

struct SyncConflictView: View {
    @Bindable private var l10n = L10nService.shared
    let conflicts: [GitHubSyncConflict]
    var onKeepLocal: (GitHubSyncConflict) -> Void = { _ in }
    var onUseRemote: (GitHubSyncConflict) -> Void = { _ in }
    var onManualMerge: (GitHubSyncConflict) -> Void = { _ in }

    var body: some View {
        List(conflicts, id: \.path) { conflict in
            VStack(alignment: .leading, spacing: 8) {
                Text(conflict.path).font(.headline).lineLimit(1)
                Text(reasonText(for: conflict.reason))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(l10n.t(.conflictKeepLocal)) { onKeepLocal(conflict) }
                        .buttonStyle(.bordered)
                    Button(l10n.t(.conflictUseRemote)) { onUseRemote(conflict) }
                        .buttonStyle(.bordered)
                    Button(l10n.t(.conflictManualMerge)) { onManualMerge(conflict) }
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(l10n.t(.conflictsTitle))
    }

    private func reasonText(for reason: GitHubSyncConflict.Reason) -> String {
        switch reason {
        case .bothModified: return l10n.t(.conflictBothModified)
        case .deleteVsModify: return l10n.t(.conflictDeleteVsModify)
        }
    }
}

// MARK: - LocalHistoryView
//
// Browse and restore per-file revisions.

struct LocalHistoryView: View {
    @Bindable private var l10n = L10nService.shared
    let path: String
    let store: LocalHistoryStore
    var onRestore: (LocalHistoryEntry) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LocalHistoryEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(l10n.t(.historyEmpty),
                                           systemImage: "clock.arrow.circlepath")
                } else {
                    List(entries.reversed(), id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date, style: .relative)
                                .font(.headline)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(entry.byteCount) \(l10n.t(.bytesUnit))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(l10n.t(.historyRestore)) { onRestore(entry) }
                                .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle(l10n.t(.historyTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.done)) { dismiss() }
                }
            }
            .onAppear { entries = store.revisions(for: path) }
        }
    }
}

// MARK: - ChangesTabView
//
// The "更改" tab: local changes vs snapshot, conflicts, patch export.

struct ChangesTabView: View {
    @Bindable private var l10n = L10nService.shared
    @Bindable var store: WorkspaceStore
    let changes: [LocalChange]
    let conflicts: [GitHubSyncConflict]
    var onExportPatch: () -> Void = {}
    var onKeepLocal: (GitHubSyncConflict) -> Void = { _ in }
    var onUseRemote: (GitHubSyncConflict) -> Void = { _ in }
    var onManualMerge: (GitHubSyncConflict) -> Void = { _ in }
    var onSync: () -> Void = {}
    var isSyncing: Bool = false
    /// False for non-GitHub projects: sync is disabled with an explanation.
    var isGitHubProject: Bool = false
    var syncError: String? = nil
    var syncNotice: String? = nil
    /// Opens the Settings sheet (owned by ContentView).
    var onShowSettings: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                if !conflicts.isEmpty {
                    Section(l10n.t(.conflictsTitle)) {
                        ForEach(conflicts, id: \.path) { conflict in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conflict.path).font(.subheadline).lineLimit(1)
                                HStack(spacing: 10) {
                                    Button(l10n.t(.conflictKeepLocal)) { onKeepLocal(conflict) }
                                    Button(l10n.t(.conflictUseRemote)) { onUseRemote(conflict) }
                                    Button(l10n.t(.conflictManualMerge)) { onManualMerge(conflict) }
                                }
                                .font(.caption).buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(l10n.t(.localChangesTitle)) {
                    if changes.isEmpty {
                        Text(l10n.t(.noLocalChanges))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(changes) { change in
                            HStack {
                                changeIcon(for: change.kind)
                                Text(change.path).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(kindText(for: change.kind))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !changes.isEmpty {
                    Section {
                        Button(l10n.t(.exportPatch)) { onExportPatch() }
                    }
                }

                Section {
                    Button {
                        onSync()
                    } label: {
                        if isSyncing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(l10n.t(.syncNow)).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSyncing || !isGitHubProject)
                    if !isGitHubProject {
                        Text(l10n.t(.githubNotAProject))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let syncError {
                        Text(syncError).font(.caption).foregroundStyle(.red)
                    }
                    if let syncNotice {
                        Text(syncNotice).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(l10n.t(.changesTab))
            // P0-1: inline title like the other three tabs — a large title is
            // exposed to XCUITest as static text and the toolbarTitleMenu does
            // not open from it; inline exposes the title as a tappable button.
            .navigationBarTitleDisplayMode(.inline)
            // P0-1: the unified workspace navigation menu lives inside the
            // tab's own NavigationStack (toolbar modifiers on the stack
            // itself would be ignored).
            .workspaceTitleMenu(store: store, onShowSettings: onShowSettings)
        }
    }

    private func changeIcon(for kind: LocalChange.Kind) -> some View {
        let (name, color): (String, Color) = switch kind {
        case .added: ("plus.circle.fill", .green)
        case .modified: ("pencil.circle.fill", .orange)
        case .deleted: ("minus.circle.fill", .red)
        }
        return Image(systemName: name).foregroundStyle(color)
    }

    private func kindText(for kind: LocalChange.Kind) -> String {
        switch kind {
        case .added: return l10n.t(.changeAdded)
        case .modified: return l10n.t(.changeModified)
        case .deleted: return l10n.t(.changeDeleted)
        }
    }
}

// MARK: - OfflineBanner

struct OfflineBanner: View {
    @Bindable private var l10n = L10nService.shared
    @Bindable var monitor = OfflineMonitor.shared

    var body: some View {
        if monitor.isOffline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                Text(l10n.t(.offlineMessage))
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.orange)
            .clipShape(Capsule())
            .padding(.top, 8)
        }
    }
}

// MARK: - SyncPlanView
//
// Shows a sync plan BEFORE it is applied: which files the remote changed
// (will be applied) and which files conflict (need manual resolution).
// The user confirms or cancels; nothing is written before confirmation.

struct SyncPlanView: View {
    @Bindable private var l10n = L10nService.shared
    let plan: GitHubSyncPlan
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        List {
            if !plan.changes.isEmpty {
                Section(l10n.t(.githubWillApply)) {
                    ForEach(plan.changes, id: \.path) { change in
                        HStack {
                            Text(change.path).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(changeKindText(for: change.kind))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !plan.conflicts.isEmpty {
                Section(l10n.t(.githubConflictsNeedResolve)) {
                    ForEach(plan.conflicts, id: \.path) { conflict in
                        Text(conflict.path).font(.subheadline).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(l10n.t(.githubSyncPlanTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(l10n.t(.cancel)) { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(l10n.t(.githubSyncConfirm)) { onConfirm() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func changeKindText(for kind: GitHubSyncChange.Kind) -> String {
        switch kind {
        case .added: return l10n.t(.changeAdded)
        case .modified: return l10n.t(.changeModified)
        case .deleted: return l10n.t(.changeDeleted)
        }
    }
}
