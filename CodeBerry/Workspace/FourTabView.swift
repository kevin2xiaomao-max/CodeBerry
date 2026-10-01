import SwiftUI

// MARK: - M5: Four-tab navigation (iPhone)
//
// iPhone bottom tabs: 文件 | 代码 | 预览 | 更改 (§44 product red line).
// iPad keeps the NavigationSplitView (files/code left, preview right).

struct FourTabView: View {
    @Bindable var store: WorkspaceStore
    @Bindable private var l10n = L10nService.shared
    @State private var selectedTab = 1  // default to Code

    var body: some View {
        TabView(selection: $selectedTab) {
            // 文件
            FileNavigatorView(store: store,
                              onBackToProjects: { store.closeProject() })
                .tabItem {
                    Label(l10n.t(.filesTab), systemImage: "folder")
                }
                .tag(0)

            // 代码
            EditorPaneView(store: store, previewInitiallyVisible: false)
                .tabItem {
                    Label(l10n.t(.codeTab), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .tag(1)

            // 预览
            PreviewTabView(store: store)
                .tabItem {
                    Label(l10n.t(.previewTab), systemImage: "eye")
                }
                .tag(2)

            // 更改
            ChangesTabContainer(store: store)
                .tabItem {
                    Label(l10n.t(.changesTab), systemImage: "arrow.triangle.branch")
                }
                .tag(3)
        }
        .onChange(of: store.openFilePath) { _, newPath in
            // Persist the selected tab in the session.
            store.saveSession(selectedTab: selectedTab)
            // Jump to Code when a file is opened from the Files tab.
            if newPath != nil { selectedTab = 1 }
        }
    }
}

// MARK: - Preview tab wrapper

/// Standalone preview for the Preview tab. Uses the store's editor text
/// and wires Preview → Code jumps back to the Code tab via notification.
struct PreviewTabView: View {
    @Bindable var store: WorkspaceStore
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        Group {
            if let path = store.openFilePath, path.hasSuffix(".swift") {
                PreviewCanvasView(
                    source: store.editorText,
                    filePath: path,
                    projectRoot: store.previewProjectRoot(),
                    projectName: store.currentProject,
                    readFile: { store.previewFileContent($0) },
                    store: store,
                    onJumpToCode: { _, _ in
                        // M5: jumping to code switches to the Code tab.
                        // (The actual file/line navigation is handled by
                        // EditorPaneView via the store.)
                        NotificationCenter.default.post(
                            name: .codeBerryJumpToCode, object: nil)
                    })
            } else {
                ContentUnavailableView(
                    l10n.t(.previewNoFile),
                    systemImage: "eye.slash",
                    description: Text(l10n.t(.previewNoFileHint)))
            }
        }
    }
}

// MARK: - Changes tab container

/// Wires ChangesTabView to live snapshot data.
struct ChangesTabContainer: View {
    @Bindable var store: WorkspaceStore
    @Bindable private var l10n = L10nService.shared
    @State private var changes: [LocalChange] = []
    @State private var patchText: String?
    @State private var showingPatch = false
    @State private var pendingPlan: GitHubSyncPlan?
    @State private var showingPlan = false
    @State private var isSyncing = false

    var body: some View {
        ChangesTabView(
            changes: changes,
            conflicts: store.syncConflicts,
            onExportPatch: exportPatch,
            onKeepLocal: resolveKeepLocal,
            onUseRemote: resolveUseRemote,
            onManualMerge: { conflict in
                // Manual merge: open the file in the editor. FourTabView's
                // onChange(of: store.openFilePath) switches to the Code tab.
                if let wsPath = store.workspacePath(ofProjectRelative: conflict.path) {
                    store.openFile(wsPath)
                }
            },
            onSync: startSync,
            isSyncing: isSyncing || store.isSyncing,
            isGitHubProject: store.githubMetadata != nil,
            syncError: store.syncError,
            syncNotice: store.syncNotice)
        .sheet(isPresented: $showingPatch) {
            if let patchText {
                NavigationStack {
                    ScrollView {
                        Text(patchText).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(l10n.t(.exportPatch))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(l10n.t(.done)) { showingPatch = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlan) {
            if let pendingPlan {
                NavigationStack {
                    SyncPlanView(plan: pendingPlan,
                                 onConfirm: confirmSync,
                                 onCancel: cancelSync)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.currentProject) { _, _ in refresh() }
    }

    /// Real local changes: current manifest vs the snapshot base (P0-2).
    private func refresh() {
        changes = store.computeLocalChanges()
    }

    /// Real unified diff: current content vs the pristine base copy (P0-2).
    private func exportPatch() {
        let diff = SnapshotChanges.unifiedDiff(
            changes: changes,
            readFile: { relative in
                guard let ws = store.workspacePath(ofProjectRelative: relative) else { return nil }
                return store.previewFileContent(ws)
            },
            readBase: { store.baseFileContent(relativePath: $0) })
        patchText = diff
        showingPatch = true
    }

    /// "立即同步": plan first, show the plan, apply only on confirmation.
    private func startSync() {
        guard !isSyncing, !store.isSyncing else { return }
        isSyncing = true
        store.syncError = nil
        store.syncNotice = nil
        Task {
            defer {
                isSyncing = false
                refresh()
            }
            do {
                let plan = try await store.planGitHubSync()
                if plan.isEmpty {
                    store.syncNotice = l10n.t(.githubSyncedUpToDate)
                } else {
                    pendingPlan = plan
                    showingPlan = true
                }
            } catch {
                store.syncError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func confirmSync() {
        showingPlan = false
        let appliedCount = pendingPlan?.changes.count ?? 0
        pendingPlan = nil
        do {
            try store.applyPendingSync()
            let conflictCount = store.syncConflicts.count
            store.syncNotice = conflictCount > 0
                ? l10n.t(.githubSyncConflicts, conflictCount)
                : l10n.t(.githubSyncApplied, appliedCount)
        } catch {
            store.syncError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
        refresh()
    }

    private func cancelSync() {
        showingPlan = false
        pendingPlan = nil
        store.discardPendingSync()
    }

    private func resolveKeepLocal(_ conflict: GitHubSyncConflict) {
        Task {
            do {
                try await store.resolveConflictKeepLocal(conflict)
            } catch {
                store.syncError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            refresh()
        }
    }

    private func resolveUseRemote(_ conflict: GitHubSyncConflict) {
        Task {
            do {
                try await store.resolveConflictUseRemote(conflict)
            } catch {
                store.syncError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            refresh()
        }
    }
}

extension Notification.Name {
    static let codeBerryJumpToCode = Notification.Name("codeBerryJumpToCode")
}
