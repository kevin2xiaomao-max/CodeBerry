import SwiftUI

@main
struct CodeBerryApp: App {
    @State private var store: WorkspaceStore
    @State private var chat: ChatViewModel
    @State private var companion = CompanionStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = WorkspaceStore()
        _store = State(initialValue: store)
        // The agent's file tools operate on the same workspace the editor shows.
        _chat = State(initialValue: ChatViewModel(workspaceURL: store.rootURL))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, chat: chat, companion: companion)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNowIfDirty() }
        }
    }
}
