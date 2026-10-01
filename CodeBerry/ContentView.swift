import SwiftUI

/// App shell (Lite build — no AI agent). Home screen lists projects; opening
/// one shows the Xcode-like split view (navigator | editor).
struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @State private var showSettings = false
    @Bindable private var l10n = L10nService.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // The project screen is a NavigationSplitView, which can't be pushed
        // onto a NavigationStack — so the push/pop animation is recreated
        // with move transitions on a ZStack swap.
        ZStack {
            if store.currentProject != nil {
                projectView
                    .transition(.move(edge: .trailing))
            } else {
                NavigationStack {
                    ProjectsListView(store: store,
                                     onShowSettings: { showSettings = true })
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.currentProject)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay(alignment: .top) {
            OfflineBanner()
        }
        .alert(l10n.t(.workspaceError),
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.lastError = nil } })) {
            Button(l10n.t(.ok), role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .onChange(of: store.selectedPath) { _, newValue in
            if let path = newValue, !store.isDirectory(path) {
                store.openFile(path)
            }
        }
        .task {
            // M5: restore the last session once on launch.
            store.restoreSession()
        }
    }

    // MARK: - M5: adaptive project layout

    /// iPhone (compact): 4-tab navigation (§44). iPad (regular): split view.
    @ViewBuilder
    private var projectView: some View {
        if sizeClass == .compact {
            FourTabView(store: store)
        } else {
            NavigationSplitView {
                FileNavigatorView(store: store,
                                  onBackToProjects: { store.closeProject() })
            } detail: {
                EditorPaneView(store: store)
                    .navigationTitle(store.openFileName ?? store.currentProject ?? "CodeBerry")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
