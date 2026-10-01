import XCTest
@testable import CodeBerry

/// P0-1 regression: the workspace can always be exited — Back to Projects
/// and Switch Workspace work from any tab and after a session restore.
/// (The UI surface is the unified `.toolbarTitleMenu` on every tab; these
/// tests pin the store semantics behind it: closeProject() exits,
/// openProject() switches, and both survive a restore.)
@MainActor
final class WorkspaceNavigationTests: XCTestCase {

    private var tmp: URL!
    private var store: WorkspaceStore!

    override func setUp() async throws {
        try await super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-nav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        store = WorkspaceStore(rootURL: tmp)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        try await super.tearDown()
    }

    private func makeProject(_ name: String) throws {
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(name),
                                                withIntermediateDirectories: true)
        store.refresh()
    }

    /// Back to Projects exits the workspace from any state.
    func testCloseProjectExitsToProjects() throws {
        try makeProject("A")
        store.openProject("A")
        XCTAssertEqual(store.currentProject, "A")

        store.closeProject()
        XCTAssertNil(store.currentProject)
        // Projects are still listed; nothing is deleted.
        XCTAssertTrue(store.projects.map(\.name).contains("A"))
    }

    /// closeProject() is idempotent — safe to trigger twice.
    func testCloseProjectIsIdempotent() throws {
        try makeProject("A")
        store.openProject("A")
        store.closeProject()
        store.closeProject()
        XCTAssertNil(store.currentProject)
    }

    /// Switch Workspace: opening another project while one is open.
    func testSwitchWorkspace() throws {
        try makeProject("A")
        try makeProject("B")
        store.openProject("A")
        store.openProject("B")
        XCTAssertEqual(store.currentProject, "B")
        // And back again.
        store.openProject("A")
        XCTAssertEqual(store.currentProject, "A")
    }

    /// After a session restore (relaunch into the project), Back to
    /// Projects still exits — the P0-1 "locked in after restart" case.
    func testCloseProjectAfterSessionRestore() throws {
        try makeProject("GH")
        store.openProject("GH")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastProjectPath"), "GH")

        // Simulate relaunch: a fresh store restores the session.
        let relaunched = WorkspaceStore(rootURL: tmp)
        XCTAssertEqual(relaunched.currentProject, "GH")

        relaunched.closeProject()
        XCTAssertNil(relaunched.currentProject)
        XCTAssertNil(UserDefaults.standard.string(forKey: "lastProjectPath"))
    }
}
