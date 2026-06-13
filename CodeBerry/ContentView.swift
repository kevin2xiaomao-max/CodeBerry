import SwiftUI

/// App shell. Home screen lists projects; opening one shows the Xcode-like
/// split view (navigator | editor). The agent chat rides along as an
/// inspector on both screens (right panel on iPad, sheet on iPhone).
struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var chat: ChatViewModel
    var companion: CompanionStore
    @State private var showChat = false
    @State private var showSettings = false

    var body: some View {
        // The project screen is a NavigationSplitView, which can't be pushed
        // onto a NavigationStack — so the push/pop animation is recreated
        // with move transitions on a ZStack swap.
        ZStack {
            if store.currentProject != nil {
                NavigationSplitView {
                    FileNavigatorView(store: store,
                                      onBackToProjects: { store.closeProject() })
                } detail: {
                    EditorPaneView(store: store)
                        .navigationTitle(store.openFileName ?? store.currentProject ?? "CodeBerry")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showChat.toggle()
                                } label: {
                                    Image(systemName: "sparkles")
                                }
                            }
                        }
                }
                .transition(.move(edge: .trailing))
            } else {
                NavigationStack {
                    ProjectsListView(store: store,
                                     onShowSettings: { showSettings = true },
                                     onToggleChat: { showChat.toggle() })
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.currentProject)
        .inspector(isPresented: $showChat) {
            ChatView(model: chat)
                .inspectorColumnWidth(min: 300, ideal: 380, max: 500)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: chat, companion: companion)
        }
        .alert("Workspace Error",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
        .onChange(of: store.currentProject, initial: true) { _, newValue in
            chat.currentProjectFolder = newValue
        }
        .onChange(of: store.selectedPath) { _, newValue in
            if let path = newValue, !store.isDirectory(path) {
                store.openFile(path)
            }
        }
        .onAppear {
            chat.onWorkspaceMutated = { [weak store] in store?.handleAgentMutation() }
            chat.onBeforeSend = { [weak store] in store?.saveNowIfDirty() }
        }
    }
}
