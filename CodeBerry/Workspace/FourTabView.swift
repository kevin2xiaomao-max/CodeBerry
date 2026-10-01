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
    @State private var changes: [LocalChange] = []
    @State private var conflicts: [GitHubSyncConflict] = []
    @State private var isSyncing = false
    @State private var patchText: String?
    @State private var showingPatch = false

    var body: some View {
        ChangesTabView(
            changes: changes,
            conflicts: conflicts,
            onExportPatch: exportPatch,
            onKeepLocal: { _ in },
            onUseRemote: { _ in },
            onManualMerge: { conflict in
                if let wsPath = store.workspacePath(ofProjectRelative: conflict.path) {
                    store.openFile(wsPath)
                }
            },
            onSync: {},
            isSyncing: isSyncing)
        .sheet(isPresented: $showingPatch) {
            if let patchText {
                NavigationStack {
                    ScrollView {
                        Text(patchText).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle(L10nService.shared.t(.exportPatch))
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        // TODO(M5): wire to GitHubRepoMetadata manifest + SyncEngine conflicts.
        // For now, compute local changes against the last-known manifest.
        changes = []
        conflicts = []
    }

    private func exportPatch() {
        let diff = SnapshotChanges.unifiedDiff(
            changes: changes,
            readFile: { store.previewFileContent($0) },
            readBase: { _ in nil })
        patchText = diff
        showingPatch = true
    }
}

extension Notification.Name {
    static let codeBerryJumpToCode = Notification.Name("codeBerryJumpToCode")
}
