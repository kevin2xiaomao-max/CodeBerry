import XCTest
@testable import CodeBerry

/// §三十九: WorkspaceSync — SnapshotSyncEngine.threeWayDiff 纯函数用例.
/// base = 上次导入/同步时的 manifest; local = 当前工作区; remote = 新快照.
final class WorkspaceSyncTests: XCTestCase {

    func testRemoteOnlyChangeApplies() {
        let base = ["a.txt": "h1",
                    "b.txt": ArchiveExtractor.sha256(of: Data("h2".utf8))]
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: base, local: base,
            remote: ["a.txt": "h1", "b.txt": "h3", "c.txt": "h4"], remoteSHA: "r")
        XCTAssertEqual(plan.conflicts, [])
        XCTAssertEqual(Set(plan.changes.map(\.path)), ["b.txt", "c.txt"])
        XCTAssertEqual(plan.changes.first { $0.path == "b.txt" }?.kind, .modified)
        XCTAssertEqual(plan.changes.first { $0.path == "c.txt" }?.kind, .added)
    }

    func testLocalOnlyChangeKept() {
        let base = ["a.txt": "h1"]
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: base, local: ["a.txt": "hLOCAL"],
            remote: ["a.txt": "h1"], remoteSHA: "r")
        XCTAssertTrue(plan.isEmpty, "local-only change must not produce a plan")
    }

    func testBothModifiedConflicts() {
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"],
            local: ["a.txt": "hLOCAL"],
            remote: ["a.txt": "hREMOTE"], remoteSHA: "r")
        XCTAssertEqual(plan.changes, [])
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertEqual(plan.conflicts.first?.reason, .bothModified)
    }

    func testDeleteVsModifyConflicts() {
        // Deleted remotely, modified locally → conflict, never auto-delete.
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"],
            local: ["a.txt": "hLOCAL"],
            remote: [:], remoteSHA: "r")
        XCTAssertEqual(plan.changes, [])
        XCTAssertEqual(plan.conflicts.first?.reason, .deleteVsModify)
    }

    func testRemoteDeleteApplies() {
        // Deleted remotely, untouched locally → safe to delete.
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1", "b.txt": "h2"],
            local: ["a.txt": "h1", "b.txt": "h2"],
            remote: ["a.txt": "h1"], remoteSHA: "r")
        XCTAssertEqual(plan.conflicts, [])
        XCTAssertEqual(plan.changes, [GitHubSyncChange(path: "b.txt", kind: .deleted)])
    }

    func testBothDeletedIsEmpty() {
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"], local: [:], remote: [:], remoteSHA: "r")
        XCTAssertTrue(plan.isEmpty)
    }

    func testIdenticalManifestsIsEmpty() {
        let m = ["a.txt": "h1", "sub/b.txt": "h2"]
        let plan = SnapshotSyncEngine.threeWayDiff(base: m, local: m, remote: m, remoteSHA: "r")
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - apply(): non-conflicting changes only

    /// Applies a plan against a real staging dir: remote-only changes land,
    /// conflicted files are untouched, metadata/manifest advance.
    func testApplyKeepsConflictedFiles() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("sync-apply-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let project = tmp.appendingPathComponent("proj")
        let staging = tmp.appendingPathComponent("staging")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        // base: a.txt=h1 b.txt=h2 | local: a edited | remote: a edited differently, b deleted, c added
        try Data("local-a".utf8).write(to: project.appendingPathComponent("a.txt"))
        try Data("h2".utf8).write(to: project.appendingPathComponent("b.txt"))
        try Data("remote-a".utf8).write(to: staging.appendingPathComponent("a.txt"))
        try Data("c".utf8).write(to: staging.appendingPathComponent("c.txt"))

        let base = ["a.txt": "h1",
                    "b.txt": ArchiveExtractor.sha256(of: Data("h2".utf8))]
        var metadata = GitHubRepoMetadata(owner: "o", repo: "r", refName: "main",
                                          refKind: .branch, baseSnapshotSHA: "old",
                                          importedAt: Date(), lastSyncAt: nil, manifest: base)

        let plan = SnapshotSyncEngine.threeWayDiff(
            base: base,
            local: ["a.txt": ArchiveExtractor.sha256(of: Data("local-a".utf8)),
                    "b.txt": ArchiveExtractor.sha256(of: Data("h2".utf8))],
            remote: ["a.txt": ArchiveExtractor.sha256(of: Data("remote-a".utf8)),
                     "c.txt": ArchiveExtractor.sha256(of: Data("c".utf8))],
            remoteSHA: "new")

        // apply() never touches the network; the client is only carried.
        let engine = SnapshotSyncEngine(client: GitHubClient(auth: AnonymousGitHubAuth()))
        metadata = try engine.apply(plan: plan, staging: staging,
                                    metadata: metadata, projectFolder: project)

        // a.txt conflicted → local content preserved.
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("a.txt")), "local-a")
        // b.txt deleted remotely, untouched locally → deleted.
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent("b.txt").path))
        // c.txt added remotely → added.
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("c.txt")), "c")
        // Metadata advanced.
        XCTAssertEqual(metadata.baseSnapshotSHA, "new")
        XCTAssertNotNil(metadata.lastSyncAt)
        XCTAssertEqual(metadata.manifest["c.txt"], ArchiveExtractor.sha256(of: Data("c".utf8)))
    }
}
