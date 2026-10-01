import SwiftUI
import Combine

// MARK: - M5: Four-tab navigation (iPhone)
//
// iPhone bottom tabs: 文件 | 代码 | 预览 | 更改 (§44 product red line).
// iPad keeps the NavigationSplitView (files/code left, preview right).

struct FourTabView: View {
    @Bindable var store: WorkspaceStore
    @Bindable private var l10n = L10nService.shared
    @State private var selectedTab = 1  // default to Code
    /// Opens the Settings sheet (owned by ContentView).
    var onShowSettings: () -> Void = {}

    var body: some View {
        TabView(selection: $selectedTab) {
            // 文件
            NavigationStack {
                FileNavigatorView(store: store,
                                  onBackToProjects: { store.closeProject() })
                    .workspaceTitleMenu(store: store, onShowSettings: onShowSettings)
            }
            .tabItem {
                Label(l10n.t(.filesTab), systemImage: "folder")
            }
            .tag(0)

            // 代码
            NavigationStack {
                EditorPaneView(store: store, previewInitiallyVisible: false)
                    .navigationTitle(store.openFileName ?? store.currentProject ?? "CodeBerry")
                    .navigationBarTitleDisplayMode(.inline)
                    .workspaceTitleMenu(store: store, onShowSettings: onShowSettings)
            }
            .tabItem {
                Label(l10n.t(.codeTab), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .tag(1)

            // 预览
            NavigationStack {
                PreviewTabView(store: store)
                    .navigationTitle(l10n.t(.previewTab))
                    .navigationBarTitleDisplayMode(.inline)
                    .workspaceTitleMenu(store: store, onShowSettings: onShowSettings)
            }
            .tabItem {
                Label(l10n.t(.previewTab), systemImage: "eye")
            }
            .tag(2)

            // 更改
            ChangesTabContainer(store: store, onShowSettings: onShowSettings)
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
        // P1-1: Preview → Code jumps. The notification carries a
        // CodeJumpRequest; switch to the Code tab, open the file, and let
        // the editor consume the pending line jump.
        .onReceive(NotificationCenter.default.publisher(for: .codeBerryJumpToCode)) { note in
            guard let request = note.object as? CodeJumpRequest else { return }
            selectedTab = store.handleCodeJumpRequest(request)
        }
    }
}

// MARK: - P0-1: unified workspace navigation menu

/// Unified native workspace navigation (P0-1): every tab gets a
/// `.toolbarTitleMenu` — Back to Projects, Switch Workspace…, Settings —
/// so the user can always leave the workspace from any tab, even after a
/// session restore. No fifth tab; the 4-tab bar is untouched.
struct WorkspaceTitleMenu: ViewModifier {
    @Bindable var store: WorkspaceStore
    @Bindable private var l10n = L10nService.shared
    var onShowSettings: () -> Void = {}

    func body(content: Content) -> some View {
        content.toolbarTitleMenu {
            Button {
                store.closeProject()
            } label: {
                Label(l10n.t(.backToProjects), systemImage: "folder")
            }
            .accessibilityIdentifier("workspace-menu-back")
            Menu {
                ForEach(store.projects) { project in
                    Button {
                        store.openProject(project.name)
                    } label: {
                        Label(project.name, systemImage: "folder.fill")
                    }
                    .disabled(project.name == store.currentProject)
                }
            } label: {
                Label(l10n.t(.switchWorkspace), systemImage: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("workspace-menu-switch")
            Button {
                onShowSettings()
            } label: {
                Label(l10n.t(.settings), systemImage: "gear")
            }
            .accessibilityIdentifier("workspace-menu-settings")
        }
    }
}

extension View {
    /// P0-1: workspace navigation title menu (Back to Projects / Switch
    /// Workspace / Settings). Apply inside a tab's NavigationStack.
    func workspaceTitleMenu(store: WorkspaceStore,
                            onShowSettings: @escaping () -> Void = {}) -> some View {
        modifier(WorkspaceTitleMenu(store: store, onShowSettings: onShowSettings))
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
                    onJumpToCode: { path, line in
                        // P1-1: carry the real target; FourTabView switches to
                        // the Code tab, opens the file, and the editor jumps
                        // to the line via the store.
                        NotificationCenter.default.post(
                            name: .codeBerryJumpToCode,
                            object: CodeJumpRequest(path: path, line: line))
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
    /// Opens the Settings sheet (owned by ContentView).
    var onShowSettings: () -> Void = {}
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
            syncNotice: store.syncNotice,
            store: store,
            onShowSettings: onShowSettings)
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

/// Payload for `.codeBerryJumpToCode`: Preview → Code navigation request.
/// `path` is workspace-relative (matches `WorkspaceStore.openFilePath`).
struct CodeJumpRequest: Equatable {
    let path: String
    let line: Int
}

extension WorkspaceStore {
    /// Handles a Preview → Code jump request (P1-1): opens the file and
    /// requests the line jump the editor will consume. Returns the Code
    /// tab index for the TabView to select.
    @discardableResult
    func handleCodeJumpRequest(_ request: CodeJumpRequest) -> Int {
        openFile(request.path)
        requestLineJump(request.line)
        return 1 // Code tab
    }
}
