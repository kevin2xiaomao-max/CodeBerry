import XCTest
@testable import CodeBerry

/// 4.0.2 P1-10: the editor's active tab stays in sync with the open file.
///
/// Regression context: on-device, the navigation title switched files
/// (XiaoZhangGuiApp.swift / UITestMode.swift / …) while the tab bar kept
/// showing the stale tab — the new tab appended off-screen was never
/// scrolled into view. These tests pin the store invariant behind the fix:
/// every navigation path (Quick Open / file tree / Jump to Definition /
/// Preview → Code all funnel through `openFile`) keeps
/// `openFilePath ∈ openTabs`, so the active tab label always equals the
/// title. (The ScrollViewReader auto-scroll itself is UI behavior.)
@MainActor
final class EditorActiveTabSyncTests: XCTestCase {

    private var tmp: URL!
    private var store: WorkspaceStore!

    override func setUp() async throws {
        try await super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-tabsync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        SessionStore.clear()
        store = WorkspaceStore(rootURL: tmp)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        SessionStore.clear()
        try await super.tearDown()
    }

    private func makeProject(_ name: String, files: [String]) throws {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files {
            try "// \(f)\n".write(to: dir.appendingPathComponent(f),
                                  atomically: true, encoding: .utf8)
        }
        store.refresh()
        store.openProject(name)
    }

    /// The invariant plus title sync, checked after every navigation step.
    private func assertTabSync(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(store.tabInvariantHolds,
                      "openFilePath must always own a tab", file: file, line: line)
        if let open = store.openFilePath {
            let activeLabels = store.openTabs.filter { $0 == open }
                .map { ($0 as NSString).lastPathComponent }
            XCTAssertEqual(activeLabels, [store.openFileName].compactMap { $0 },
                           "active tab label must equal the navigation title",
                           file: file, line: line)
        }
    }

    /// The exact on-device sequence from the bug report: title switched
    /// across XiaoZhangGuiApp / UITestMode / ReleaseNotes while the tab bar
    /// lagged on RootView.
    func testRapidFileSwitchesKeepActiveTabInSync() throws {
        try makeProject("P", files: ["RootView.swift", "XiaoZhangGuiApp.swift",
                                     "UITestMode.swift", "ReleaseNotes.swift"])
        for file in ["RootView.swift", "XiaoZhangGuiApp.swift",
                     "UITestMode.swift", "ReleaseNotes.swift",
                     "RootView.swift", "ReleaseNotes.swift"] {
            store.openFile("P/\(file)")
            XCTAssertEqual(store.openFileName, file)
            assertTabSync()
        }
        // Every visited file owns a tab, in visit order.
        XCTAssertEqual(store.openTabs,
                       ["P/RootView.swift", "P/XiaoZhangGuiApp.swift",
                        "P/UITestMode.swift", "P/ReleaseNotes.swift"])
    }

    /// Preview → Code jumps (P1-1 path) update the active tab too.
    func testPreviewToCodeJumpKeepsActiveTabInSync() throws {
        try makeProject("P", files: ["RootView.swift", "HomeView.swift"])
        store.openFile("P/RootView.swift")
        _ = store.handleCodeJumpRequest(CodeJumpRequest(path: "P/HomeView.swift", line: 42))
        XCTAssertEqual(store.openFileName, "HomeView.swift")
        assertTabSync()
    }

    /// Closing tabs (active or not) preserves the invariant.
    func testCloseTabKeepsInvariant() throws {
        try makeProject("P", files: ["A.swift", "B.swift", "C.swift"])
        store.openFile("P/A.swift")
        store.openFile("P/B.swift")
        store.openFile("P/C.swift")
        // Close a background tab.
        store.closeTab("P/A.swift")
        XCTAssertEqual(store.openFileName, "C.swift")
        assertTabSync()
        // Close the active tab → falls back to the most recent tab.
        store.closeTab("P/C.swift")
        XCTAssertEqual(store.openFileName, "B.swift")
        assertTabSync()
        // Close everything → no active file, invariant holds vacuously.
        store.closeTab("P/B.swift")
        XCTAssertNil(store.openFilePath)
        assertTabSync()
    }

    /// Re-opening the already-active file never duplicates its tab.
    func testReopenActiveFileDoesNotDuplicateTab() throws {
        try makeProject("P", files: ["A.swift"])
        store.openFile("P/A.swift")
        store.openFile("P/A.swift")
        XCTAssertEqual(store.openTabs, ["P/A.swift"])
        assertTabSync()
    }
}
