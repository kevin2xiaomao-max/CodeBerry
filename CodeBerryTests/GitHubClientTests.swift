import XCTest
@testable import CodeBerry

/// §三十九: GitHubClient — mocked transport: DTO 解码 / 错误映射 / 限流.
final class GitHubClientTests: XCTestCase {

    // MARK: - Mock transport

    private final class MockProtocol: URLProtocol {
        /// path → (status, headers, body)
        /// Test-only shared state; tests set routes then await one request at
        /// a time, so `nonisolated(unsafe)` documents the single-flight use.
        nonisolated(unsafe) static var routes: [String: (Int, [String: String], Data)] = [:]
        nonisolated(unsafe) static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            // `URL.path` excludes the query string, so paged requests
            // (`…/branches?per_page=100&page=1`) match the plain path key.
            let path = request.url?.path ?? ""
            let (status, headers, body) = Self.routes[path]
                ?? (404, [:], Data("{\"message\":\"Not Found\"}".utf8))
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: nil,
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeClient(routes: [String: (Int, [String: String], Data)],
                            auth: GitHubAuthProvider = AnonymousGitHubAuth()) -> GitHubClient {
        MockProtocol.routes = routes
        MockProtocol.lastRequest = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return GitHubClient(auth: auth, session: URLSession(configuration: config))
    }

    private func json(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Tests

    func testRepoInfoDecoding() async throws {
        let client = makeClient(routes: [
            "/repos/octocat/Hello-World": (200, [:], json("""
                {"name":"Hello-World","full_name":"octocat/Hello-World",
                 "private":false,"default_branch":"master",
                 "description":"My first repo","updated_at":"2024-01-01T00:00:00Z"}
                """)),
        ])
        let info = try await client.repoInfo(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(info.fullName, "octocat/Hello-World")
        XCTAssertEqual(info.defaultBranch, "master")
        XCTAssertFalse(info.isPrivate)
    }

    func testAuthHeaderSent() async throws {
        let client = makeClient(
            routes: ["/repos/o/r": (200, [:], json(
                #"{"name":"r","full_name":"o/r","private":true,"default_branch":"main"}"#))],
            auth: TokenGitHubAuth(token: "ghp_test123"))
        _ = try await client.repoInfo(owner: "o", repo: "r")
        XCTAssertEqual(MockProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer ghp_test123")
    }

    func testAnonymousSendsNoAuthHeader() async throws {
        let client = makeClient(routes: [
            "/repos/o/r": (200, [:], json(
                #"{"name":"r","full_name":"o/r","private":false,"default_branch":"main"}"#)),
        ])
        _ = try await client.repoInfo(owner: "o", repo: "r")
        XCTAssertNil(MockProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testNotFoundMapping() async {
        let client = makeClient(routes: [:])
        do {
            _ = try await client.repoInfo(owner: "no", repo: "such-repo")
            XCTFail("expected throw")
        } catch let e as GitHubError {
            if case .http(let status, _) = e { XCTAssertEqual(status, 404) }
            else { XCTFail("wrong error: \(e)") }
        } catch { XCTFail("wrong error type: \(error)") }
    }

    func testUnauthorizedMapping() async {
        let client = makeClient(routes: [
            "/repos/o/private-repo": (401, [:], json(#"{"message":"Bad credentials"}"#)),
        ], auth: TokenGitHubAuth(token: "ghp_bad"))
        do {
            _ = try await client.repoInfo(owner: "o", repo: "private-repo")
            XCTFail("expected throw")
        } catch let e as GitHubError {
            if case .unauthorized = e { } else { XCTFail("wrong error: \(e)") }
        } catch { XCTFail("wrong error type") }
    }

    func testRateLimitedMapping() async {
        let reset = String(Int(Date().addingTimeInterval(60).timeIntervalSince1970))
        let client = makeClient(routes: [
            "/repos/o/r": (403,
                           ["x-ratelimit-remaining": "0",
                            "x-ratelimit-limit": "60",
                            "x-ratelimit-reset": reset],
                           json(#"{"message":"API rate limit exceeded"}"#)),
        ])
        do {
            _ = try await client.repoInfo(owner: "o", repo: "r")
            XCTFail("expected throw")
        } catch let e as GitHubError {
            if case .rateLimited(let date) = e {
                XCTAssertNotNil(date)
            } else { XCTFail("wrong error: \(e)") }
        } catch { XCTFail("wrong error type") }
    }

    func testBranchListDecoding() async throws {
        // Fewer than perPage → single page, no follow-up requests.
        let client = makeClient(routes: [
            "/repos/o/r/branches": (200, [:], json(
                #"[{"name":"main","commit":{"sha":"sha1"}},{"name":"dev","commit":{"sha":"sha2"}}]"#)),
        ])
        let branches = try await client.branches(owner: "o", repo: "r")
        XCTAssertEqual(branches.count, 2)
        XCTAssertEqual(branches.first?.sha, "sha1")
        XCTAssertEqual(branches.last?.name, "dev")
    }

    func testResolveBranch() async throws {
        let client = makeClient(routes: [
            "/repos/o/r/branches": (200, [:], json(#"[{"name":"main","commit":{"sha":"abc123"}}]"#)),
        ])
        let parsed = try GitHubURLParser.parse("https://github.com/o/r/tree/main")
        let resolved = try await client.resolve(parsed)
        XCTAssertEqual(resolved.kind, .branch)
        XCTAssertEqual(resolved.sha, "abc123")
    }

    func testResolveCommitValidatesSHA() async throws {
        let client = makeClient(routes: [
            "/repos/o/r/commits/deadbeef": (200, [:], json(#"{"sha":"deadbeef"}"#)),
        ])
        let parsed = try GitHubURLParser.parse("https://github.com/o/r/commit/deadbeef")
        let resolved = try await client.resolve(parsed)
        XCTAssertEqual(resolved.kind, .commit)
        XCTAssertEqual(resolved.sha, "deadbeef")
    }

    func testTagPeeling() async throws {
        let client = makeClient(routes: [
            "/repos/o/r/git/ref/tags/v1.0": (200, [:], json(
                #"{"object":{"sha":"tagsah123","type":"tag"}}"#)),
            "/repos/o/r/git/tags/tagsah123": (200, [:], json(
                #"{"object":{"sha":"commitsha456","type":"commit"}}"#)),
        ])
        let sha = try await client.tagCommitSHA(owner: "o", repo: "r", tag: "v1.0")
        XCTAssertEqual(sha, "commitsha456")
    }

    func testSnapshotURLPinsSHA() {
        let client = GitHubClient(auth: AnonymousGitHubAuth())
        let url = client.snapshotURL(owner: "o", repo: "r", sha: "abc123")
        XCTAssertEqual(url.absoluteString,
                       "https://api.github.com/repos/o/r/zipball/abc123")
    }
}
