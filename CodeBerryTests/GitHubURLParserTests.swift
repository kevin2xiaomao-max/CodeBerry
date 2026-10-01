import XCTest
@testable import CodeBerry

/// §三十九: GitHubURLParser — 三种 URL 形态 + SSH 形式.
final class GitHubURLParserTests: XCTestCase {

    func testRepoRoot() throws {
        let r = try GitHubURLParser.parse("https://github.com/kevin2xiaomao-max/XiaoZhangGui")
        XCTAssertEqual(r.owner, "kevin2xiaomao-max")
        XCTAssertEqual(r.repo, "XiaoZhangGui")
        XCTAssertEqual(r.refKind, .defaultBranch)
        XCTAssertNil(r.refName)
        XCTAssertNil(r.filePath)
    }

    func testRepoRootWithGitSuffix() throws {
        let r = try GitHubURLParser.parse("https://github.com/octocat/Hello-World.git")
        XCTAssertEqual(r.owner, "octocat")
        XCTAssertEqual(r.repo, "Hello-World")
        XCTAssertEqual(r.refKind, .defaultBranch)
    }

    func testTreeBranch() throws {
        let r = try GitHubURLParser.parse(
            "https://github.com/kevin2xiaomao-max/XiaoZhangGui/tree/main")
        XCTAssertEqual(r.refKind, .branch)
        XCTAssertEqual(r.refName, "main")
        XCTAssertNil(r.filePath)
    }

    func testTreeBranchWithPath() throws {
        // Note: branch names with slashes are split naively here; the import
        // flow disambiguates against the branch list (longest match).
        let r = try GitHubURLParser.parse(
            "https://github.com/kevin2xiaomao-max/XiaoZhangGui/tree/feature/v3.6.1")
        XCTAssertEqual(r.refKind, .branch)
        XCTAssertEqual(r.refName, "feature")
        XCTAssertEqual(r.filePath, "v3.6.1")
    }

    func testBlobFile() throws {
        let r = try GitHubURLParser.parse(
            "https://github.com/octocat/Hello-World/blob/master/README")
        XCTAssertEqual(r.refKind, .branch)
        XCTAssertEqual(r.refName, "master")
        XCTAssertEqual(r.filePath, "README")
    }

    func testBlobNestedPath() throws {
        let r = try GitHubURLParser.parse(
            "https://github.com/owner/repo/blob/main/Sources/App/ContentView.swift")
        XCTAssertEqual(r.filePath, "Sources/App/ContentView.swift")
    }

    func testBlobWithoutPathFails() {
        XCTAssertThrowsError(
            try GitHubURLParser.parse("https://github.com/owner/repo/blob/main")) { error in
            XCTAssertEqual(error as? GitHubURLParserError, .unsupportedForm)
        }
    }

    func testCommitURL() throws {
        let r = try GitHubURLParser.parse(
            "https://github.com/owner/repo/commit/660533013dc0d2bb4e5a81924333322e1d204431")
        XCTAssertEqual(r.refKind, .commit)
        XCTAssertEqual(r.refName, "660533013dc0d2bb4e5a81924333322e1d204431")
    }

    func testSSHScpForm() throws {
        let r = try GitHubURLParser.parse("git@github.com:octocat/Hello-World.git")
        XCTAssertEqual(r.owner, "octocat")
        XCTAssertEqual(r.repo, "Hello-World")
        XCTAssertEqual(r.refKind, .defaultBranch)
    }

    func testSSHURLForm() throws {
        let r = try GitHubURLParser.parse("ssh://git@github.com/octocat/Hello-World")
        XCTAssertEqual(r.owner, "octocat")
        XCTAssertEqual(r.repo, "Hello-World")
        XCTAssertEqual(r.refKind, .defaultBranch)
    }

    func testNonGitHubRejected() {
        XCTAssertThrowsError(try GitHubURLParser.parse("https://gitlab.com/owner/repo")) { error in
            XCTAssertEqual(error as? GitHubURLParserError, .notGitHubURL)
        }
    }

    func testMissingRepoRejected() {
        XCTAssertThrowsError(try GitHubURLParser.parse("https://github.com/onlyowner")) { error in
            XCTAssertEqual(error as? GitHubURLParserError, .missingOwnerOrRepo)
        }
    }

    func testWhitespaceTrimmed() throws {
        let r = try GitHubURLParser.parse("  https://github.com/octocat/Hello-World\n")
        XCTAssertEqual(r.repo, "Hello-World")
    }

    func testDisplayRef() throws {
        let b = try GitHubURLParser.parse("https://github.com/o/r/tree/main")
        XCTAssertEqual(b.displayRef, "main")
        let c = try GitHubURLParser.parse("https://github.com/o/r/commit/660533013dc0d2bb4e5a81924333322e1d204431")
        XCTAssertEqual(c.displayRef, "6605330")
        let d = try GitHubURLParser.parse("https://github.com/o/r")
        XCTAssertEqual(d.displayRef, "default")
    }
}
