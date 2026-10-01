import XCTest
@testable import CodeBerry

/// P0-2 regression: the Changes tab is wired to the real SnapshotSyncEngine —
/// real local changes from the manifest, real plan → apply, and real conflict
/// resolution (Keep Local / Use Remote) against a retained staging snapshot.
@MainActor
final class WorkspaceSyncOrchestrationTests: XCTestCase {

    private var tmp: URL!
    private var store: WorkspaceStore!

    override func setUp() async throws {
        try await super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Isolate session restore: never reopen a foreign project.
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

    // MARK: - Helpers

    private func sha(_ s: String) -> String {
        ArchiveExtractor.sha256(of: Data(s.utf8))
    }

    /// Creates a GitHub project folder with metadata + pristine base copy.
    @discardableResult
    private func makeGitHubProject(name: String = "GH",
                                   files: [String: String]) throws -> URL {
        let projectDir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: projectDir,
                                                withIntermediateDirectories: true)
        for (path, content) in files {
            let url = projectDir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let metadata = GitHubRepoMetadata(
            owner: "o", repo: "r", refName: "main", refKind: .branch,
            baseSnapshotSHA: "abc123", importedAt: Date(), lastSyncAt: nil,
            manifest: GitHubRepoMetadata.buildManifest(projectFolder: projectDir))
        try metadata.save(projectFolder: projectDir)
        try SnapshotSyncEngine.installBaseCopy(projectFolder: projectDir)
        return projectDir
    }

    private func write(_ content: String, to relative: String, in project: URL) throws {
        try Data(content.utf8).write(to: project.appendingPathComponent(relative))
    }

    // MARK: - Metadata state

    func testRefreshGitHubStateLoadsMetadata() throws {
        try makeGitHubProject(files: ["a.txt": "hello"])
        store.openProject("GH")
        let metadata = try XCTUnwrap(store.githubMetadata)
        XCTAssertEqual(metadata.owner, "o")
        XCTAssertEqual(metadata.baseSnapshotSHA, "abc123")
        XCTAssertEqual(metadata.manifest["a.txt"], sha("hello"))
    }

    func testGitHubStateNilForPlainProject() {
        // The bootstrapped Welcome project has no .github-repo.json.
        store.openProject("Welcome")
        XCTAssertNil(store.githubMetadata)
    }

    func testGitHubStateClearedOnClose() throws {
        try makeGitHubProject(files: ["a.txt": "hello"])
        store.openProject("GH")
        XCTAssertNotNil(store.githubMetadata)
        store.closeProject()
        XCTAssertNil(store.githubMetadata)
    }

    // MARK: - Local changes

    func testComputeLocalChangesFindsRealChanges() throws {
        let project = try makeGitHubProject(files: ["a.txt": "base-a",
                                                    "b.txt": "base-b"])
        store.openProject("GH")
        XCTAssertTrue(store.computeLocalChanges().isEmpty)

        try write("local-a", to: "a.txt", in: project)          // modified
        try FileManager.default.removeItem(at: project.appendingPathComponent("b.txt")) // deleted
        try write("new-c", to: "c.txt", in: project)            // added

        let changes = store.computeLocalChanges()
        XCTAssertEqual(changes.count, 3)
        let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0.kind) })
        XCTAssertEqual(byPath["a.txt"], .modified)
        XCTAssertEqual(byPath["b.txt"], .deleted)
        XCTAssertEqual(byPath["c.txt"], .added)
    }

    func testComputeLocalChangesEmptyForNonGitHubProject() {
        store.openProject("Welcome")
        XCTAssertTrue(store.computeLocalChanges().isEmpty)
    }

    // MARK: - Pristine base (patch export readBase)

    func testBaseFileContentReadsPristineBase() throws {
        let project = try makeGitHubProject(files: ["a.txt": "v1"])
        // Local edit AFTER the base copy was installed.
        try write("v2-local", to: "a.txt", in: project)
        store.openProject("GH")
        XCTAssertEqual(store.baseFileContent(relativePath: "a.txt"), "v1")
    }

    func testBaseFileContentRejectsTraversal() throws {
        try makeGitHubProject(files: ["a.txt": "v1"])
        store.openProject("GH")
        XCTAssertNil(store.baseFileContent(relativePath: "../escape.txt"))
        XCTAssertNil(store.baseFileContent(relativePath: "missing.txt"))
    }

    // MARK: - plan → apply → resolve (offline, injected staging)

    /// Full offline flow: inject a pending sync with a conflict, apply it
    /// (conflict survives), then resolve Keep Local.
    func testApplyThenKeepLocal() async throws {
        let project = try makeGitHubProject(files: ["a.txt": "B-local"])
        let staging = tmp.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("C-remote".utf8).write(to: staging.appendingPathComponent("a.txt"))
        store.openProject("GH")

        let conflict = GitHubSyncConflict(path: "a.txt", reason: .bothModified)
        let plan = GitHubSyncPlan(changes: [], conflicts: [conflict], remoteSHA: "C")
        store.injectPendingSyncForTesting(plan: plan, staging: staging,
                                          remoteManifest: ["a.txt": sha("C-remote")])

        try store.applyPendingSync()
        // Conflict survived the apply; local content untouched.
        XCTAssertEqual(store.syncConflicts, [conflict])
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("a.txt"),
                                   encoding: .utf8), "B-local")

        try await store.resolveConflictKeepLocal(conflict)
        // Local content wins; base advances to the remote hash (P1-2: the
        // next diff stays quiet until remote moves again).
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("a.txt"),
                                   encoding: .utf8), "B-local")
        XCTAssertEqual(store.githubMetadata?.manifest["a.txt"], sha("C-remote"))
        XCTAssertEqual(store.baseFileContent(relativePath: "a.txt"), "C-remote")
        XCTAssertTrue(store.syncConflicts.isEmpty)
    }

    func testApplyThenUseRemote() async throws {
        let project = try makeGitHubProject(files: ["a.txt": "B-local"])
        let staging = tmp.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("C-remote".utf8).write(to: staging.appendingPathComponent("a.txt"))
        store.openProject("GH")

        let conflict = GitHubSyncConflict(path: "a.txt", reason: .bothModified)
        let plan = GitHubSyncPlan(changes: [], conflicts: [conflict], remoteSHA: "C")
        store.injectPendingSyncForTesting(plan: plan, staging: staging,
                                          remoteManifest: ["a.txt": sha("C-remote")])

        try store.applyPendingSync()
        try await store.resolveConflictUseRemote(conflict)
        // Remote content wins everywhere: file, manifest base, pristine copy.
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("a.txt"),
                                   encoding: .utf8), "C-remote")
        XCTAssertEqual(store.githubMetadata?.manifest["a.txt"], sha("C-remote"))
        XCTAssertEqual(store.baseFileContent(relativePath: "a.txt"), "C-remote")
        XCTAssertTrue(store.syncConflicts.isEmpty)
    }

    func testPlanGitHubSyncThrowsForNonGitHubProject() async {
        store.openProject("Welcome")
        await XCTAssertThrowsError(try await store.planGitHubSync()) { error in
            XCTAssertTrue(error is WorkspaceSyncError)
        }
    }
}
