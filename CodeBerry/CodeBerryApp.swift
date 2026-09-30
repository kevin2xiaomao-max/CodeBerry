import SwiftUI

@main
struct CodeBerryApp: App {
    @State private var store: WorkspaceStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _store = State(initialValue: WorkspaceStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNowIfDirty() }
        }
    }
}
