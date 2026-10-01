import XCTest
@testable import CodeBerry

/// §三十七/§三十八: 真实 E2E — 对真实 GitHub API 与真实仓库跑完整链路:
/// 解析 URL → 解析 ref → 下载 snapshot → 安全解压 → 导入 → 校验文件树 →
/// manifest → 同步 (无变化时零下载).
///
/// UI 点按步骤 (import sheet / 同步按钮) 由单元测试 + CI 集成覆盖,
/// 真机点按待用户用 IPA 验收 (见 M1_REPORT).
///
/// 配额保护: 匿名 60 req/h. 剩余配额 < 20 时 skip, 避免把 CI 配额耗尽.
final class GitHubE2EIntegrationTests: XCTestCase {

    private var tmp: URL!
    private var client: GitHubClient!

    override func setUp() async throws {
        try await super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Optional PAT for higher quota: `GITHUB_TEST_TOKEN` env (CI: unset).
        let auth: GitHubAuthProvider
        if let token = ProcessInfo.processInfo.environment["GITHUB_TEST_TOKEN"],
           !token.isEmpty {
            auth = TokenGitHubAuth(token: token)
        } else {
            auth = AnonymousGitHubAuth()
        }
        client = GitHubClient(auth: auth)

        let budget = try await client.rateLimit()
        try XCTSkipIf(budget.remaining < 20,
                      "GitHub API quota too low (\(budget.remaining) left); skipping live E2E.")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    // MARK: - §38: small public repo (octocat/Hello-World)

    /// Full pipeline on a tiny public repo: import → verify tree → sync is a
    /// no-op (HEAD == base, so no second download happens).
    func testSmallPublicRepoImportAndSync() async throws {
        let parsed = try GitHubURLParser.parse("https://github.com/octocat/Hello-World")
        let info = try await client.repoInfo(owner: parsed.owner, repo: parsed.repo)
        XCTAssertEqual(info.defaultBranch, "master")

        let resolved = try await client.resolve(parsed)
        XCTAssertEqual(resolved.kind, .defaultBranch)
        XCTAssertFalse(resolved.sha.isEmpty)

        let engine = SnapshotSyncEngine(client: client)
        let folder = try await engine.importRepo(parsed: parsed, resolved: resolved,
                                                 workspaceRoot: tmp) { _ in }
        let projectFolder = tmp.appendingPathComponent(folder)
        let metadata = try XCTUnwrap(GitHubRepoMetadata.load(projectFolder: projectFolder))
        XCTAssertEqual(metadata.owner, "octocat")
        XCTAssertEqual(metadata.repo, "Hello-World")
        XCTAssertEqual(metadata.baseSnapshotSHA, resolved.sha)
        XCTAssertFalse(metadata.manifest.isEmpty)
        // Hello-World contains a README file.
        XCTAssertTrue(metadata.manifest.keys.contains { $0.hasSuffix("README") },
                      "expected a README in \(metadata.manifest.keys.sorted())")

        // Sync right after import: remote HEAD == base → empty plan, no download.
        let (plan, staging) = try await engine.planSync(projectFolder: projectFolder,
                                                        metadata: metadata) { _ in }
        engine.discardStaging(staging)
        XCTAssertTrue(plan.isEmpty, "fresh import must sync to an empty plan")
        XCTAssertNil(staging, "empty plan must not download a staging snapshot")
    }

    // MARK: - §37: XiaoZhangGui (real app repo, slashed branch)

    func testXiaoZhangGuiBranchImport() async throws {
        let owner = "kevin2xiaomao-max", repo = "XiaoZhangGui"
        let branch = "feature/v3.6.1-reference-home"

        // Slash-branch disambiguation: parser splits naively, the client
        // re-joins against the branch list (longest match).
        let match = try await client.matchBranch(owner: owner, repo: repo,
                                                 name: "feature",
                                                 extraPath: "v3.6.1-reference-home")
        let (matchedName, head) = try XCTUnwrap(match, "branch \(branch) must exist")
        XCTAssertEqual(matchedName, branch)
        XCTAssertEqual(String(head.prefix(7)), "6605330")

        let parsed = GitHubRepoRef(owner: owner, repo: repo, refKind: .branch,
                                   refName: branch, filePath: nil)
        let resolved = try await client.resolve(parsed)
        XCTAssertEqual(resolved.sha, head)

        let engine = SnapshotSyncEngine(client: client)
        let folder = try await engine.importRepo(parsed: parsed, resolved: resolved,
                                                 workspaceRoot: tmp) { _ in }
        let projectFolder = tmp.appendingPathComponent(folder)
        let metadata = try XCTUnwrap(GitHubRepoMetadata.load(projectFolder: projectFolder))
        // A real app repo: expect a substantial tree with Swift sources.
        XCTAssertGreaterThan(metadata.manifest.count, 10)
        XCTAssertTrue(metadata.manifest.keys.contains { $0.hasSuffix(".swift") },
                      "expected Swift sources in the imported tree")
    }

    // MARK: - threeWayDiff (pure, no network)

    func testThreeWayDiffRemoteOnlyChange() {
        let base = ["a.txt": "h1", "b.txt": "h2"]
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: base, local: base,
            remote: ["a.txt": "h1", "b.txt": "h3", "c.txt": "h4"], remoteSHA: "r")
        XCTAssertEqual(plan.conflicts, [])
        XCTAssertEqual(Set(plan.changes.map(\.path)), ["b.txt", "c.txt"])
        XCTAssertEqual(plan.changes.first { $0.path == "b.txt" }?.kind, .modified)
        XCTAssertEqual(plan.changes.first { $0.path == "c.txt" }?.kind, .added)
    }

    func testThreeWayDiffLocalOnlyChangeKept() {
        let base = ["a.txt": "h1"]
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: base, local: ["a.txt": "hLOCAL"],
            remote: ["a.txt": "h1"], remoteSHA: "r")
        XCTAssertTrue(plan.isEmpty, "local-only change must not produce a plan")
    }

    func testThreeWayDiffBothModifiedConflicts() {
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"],
            local: ["a.txt": "hLOCAL"],
            remote: ["a.txt": "hREMOTE"], remoteSHA: "r")
        XCTAssertEqual(plan.changes, [])
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertEqual(plan.conflicts.first?.reason, .bothModified)
    }

    func testThreeWayDiffDeleteVsModifyConflicts() {
        // Deleted remotely, modified locally → conflict, never auto-delete.
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"],
            local: ["a.txt": "hLOCAL"],
            remote: [:], remoteSHA: "r")
        XCTAssertEqual(plan.changes, [])
        XCTAssertEqual(plan.conflicts.first?.reason, .deleteVsModify)
    }

    func testThreeWayDiffRemoteDeleteApplies() {
        // Deleted remotely, untouched locally → safe to delete.
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1", "b.txt": "h2"],
            local: ["a.txt": "h1", "b.txt": "h2"],
            remote: ["a.txt": "h1"], remoteSHA: "r")
        XCTAssertEqual(plan.conflicts, [])
        XCTAssertEqual(plan.changes, [GitHubSyncChange(path: "b.txt", kind: .deleted)])
    }

    func testThreeWayDiffBothDeletedIsEmpty() {
        let plan = SnapshotSyncEngine.threeWayDiff(
            base: ["a.txt": "h1"], local: [:], remote: [:], remoteSHA: "r")
        XCTAssertTrue(plan.isEmpty)
    }
}
