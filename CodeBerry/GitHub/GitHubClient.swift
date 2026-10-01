import Foundation

/// Errors from the GitHub REST layer (§8).
enum GitHubError: Error, LocalizedError {
    case invalidURL
    case network(URLError)
    case http(status: Int, message: String)
    case rateLimited(reset: Date?)
    case notFound(owner: String, repo: String)
    case unauthorized
    case decoding
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L10nService.shared.t(.errGithubInvalidURL)
        case .network(let e): return L10nService.shared.t(.errGithubNetwork, e.localizedDescription)
        case .http(let s, let m): return L10nService.shared.t(.errGithubHTTP, String(s), m)
        case .rateLimited(let reset):
            if let reset {
                return L10nService.shared.t(.errGithubRateLimited,
                                            reset.formatted(date: .omitted, time: .shortened))
            }
            return L10nService.shared.t(.errGithubRateLimitedUnknown)
        case .notFound(let o, let r): return L10nService.shared.t(.errGithubNotFound, "\(o)/\(r)")
        case .unauthorized: return L10nService.shared.t(.errGithubUnauthorized)
        case .decoding: return L10nService.shared.t(.errGithubDecoding)
        case .cancelled: return L10nService.shared.t(.errGithubCancelled)
        }
    }
}

// MARK: - DTOs

struct GitHubRepoInfo: Decodable, Equatable {
    let name: String
    let fullName: String
    let isPrivate: Bool
    let defaultBranch: String
    let description: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case description
        case updatedAt = "updated_at"
    }
}

struct GitHubBranch: Decodable, Equatable, Identifiable {
    let name: String
    let sha: String
    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, commit }
    struct Commit: Decodable { let sha: String }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sha = try c.decode(Commit.self, forKey: .commit).sha
    }
}

struct GitHubTag: Decodable, Equatable, Identifiable {
    let name: String
    var id: String { name }
}

/// A ref resolved to an immutable commit SHA (§8: 下载永远按 SHA).
struct GitHubResolvedRef: Equatable {
    let kind: GitHubRefKind
    /// Display name: branch/tag name, "default", or short SHA for commits.
    let name: String
    let sha: String
}

struct GitHubRateLimit: Equatable {
    let limit: Int
    let remaining: Int
    let reset: Date
}

// MARK: - Client

/// Minimal GitHub REST client (§8). URLSession only, no third-party deps.
/// All snapshot downloads go through `snapshotURL(owner:repo:sha:)` so the
/// downloaded content is pinned to an immutable commit SHA.
// @unchecked Sendable: all stored state (`auth`, `session`) is immutable after init.
final class GitHubClient: @unchecked Sendable {
    private static let apiBase = "https://api.github.com"
    private static let maxPages = 3
    private static let perPage = 100

    let auth: GitHubAuthProvider
    private let session: URLSession

    init(auth: GitHubAuthProvider, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Public API

    /// `GET /repos/{owner}/{repo}`
    func repoInfo(owner: String, repo: String) async throws -> GitHubRepoInfo {
        try await get(path: "/repos/\(owner)/\(repo)")
    }

    /// `GET /repos/{o}/{r}/branches` (paginated, capped).
    func branches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try await paged(path: "/repos/\(owner)/\(repo)/branches")
    }

    /// `GET /repos/{o}/{r}/tags` (paginated, capped).
    func tags(owner: String, repo: String) async throws -> [GitHubTag] {
        try await paged(path: "/repos/\(owner)/\(repo)/tags")
    }

    /// Current rate-limit budget for this auth identity.
    func rateLimit() async throws -> GitHubRateLimit {
        let (_, response) = try await data(path: "/rate_limit")
        guard let http = response as? HTTPURLResponse else { throw GitHubError.decoding }
        return try Self.rateLimit(from: http)
    }

    /// Resolve a parsed URL ref to an immutable commit SHA.
    /// Order: default branch → branch → tag → raw commit SHA.
    func resolve(_ parsed: GitHubRepoRef) async throws -> GitHubResolvedRef {
        switch parsed.refKind {
        case .defaultBranch:
            let info = try await repoInfo(owner: parsed.owner, repo: parsed.repo)
            let head = try await branchHead(owner: parsed.owner, repo: parsed.repo,
                                            branch: info.defaultBranch)
            return GitHubResolvedRef(kind: .defaultBranch, name: info.defaultBranch, sha: head)
        case .branch:
            let name = parsed.refName ?? ""
            // Branch names may contain slashes; the URL parser splits naively
            // (`tree/feature/v3.6.1` → ref=`feature`, filePath=`v3.6.1`), so
            // re-join against the branch list, longest match first.
            if let match = try await matchBranch(owner: parsed.owner, repo: parsed.repo,
                                                 name: name, extraPath: parsed.filePath) {
                return GitHubResolvedRef(kind: .branch, name: match.name, sha: match.sha)
            }
            // Fall through: maybe it was actually a tag.
            if let sha = try await tagCommitSHA(owner: parsed.owner, repo: parsed.repo, tag: name) {
                return GitHubResolvedRef(kind: .tag, name: name, sha: sha)
            }
            throw GitHubError.notFound(owner: parsed.owner, repo: "\(parsed.repo)@\(name)")
        case .tag:
            let name = parsed.refName ?? ""
            if let sha = try await tagCommitSHA(owner: parsed.owner, repo: parsed.repo, tag: name) {
                return GitHubResolvedRef(kind: .tag, name: name, sha: sha)
            }
            throw GitHubError.notFound(owner: parsed.owner, repo: "\(parsed.repo)@\(name)")
        case .commit:
            let sha = parsed.refName ?? ""
            // Validate the SHA exists.
            _ = try await get(path: "/repos/\(parsed.owner)/\(parsed.repo)/commits/\(sha)",
                              as: GitHubCommit.self)
            return GitHubResolvedRef(kind: .commit, name: String(sha.prefix(7)), sha: sha)
        }
    }

    /// `GET /repos/{o}/{r}/zipball/{sha}` — 302s to codeload; URLSession
    /// follows the redirect. Auth header is forwarded on same-host redirects
    /// only; the API endpoint keeps the token, codeload gets a signed URL.
    func snapshotURL(owner: String, repo: String, sha: String) -> URL {
        URL(string: "\(Self.apiBase)/repos/\(owner)/\(repo)/zipball/\(sha)")!
    }

    // MARK: - Ref helpers

    /// `GET /repos/{o}/{r}/branches/{branch}` → HEAD SHA.
    func branchHead(owner: String, repo: String, branch: String) async throws -> String {
        let b: GitHubBranch = try await get(
            path: "/repos/\(owner)/\(repo)/branches/\(branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch)")
        return b.sha
    }

    /// Branch list lookup that tolerates slashes in branch names: the URL
    /// parser may have split `feature/v3.6.1` into ref=`feature`,
    /// path=`v3.6.1`. Try the full `name/path…` join first (longest match).
    /// Returns the matched branch name and its HEAD SHA.
    func matchBranch(owner: String, repo: String, name: String,
                     extraPath: String? = nil) async throws -> (name: String, sha: String)? {
        let list = try await branches(owner: owner, repo: repo)
        var candidates = [name]
        if let extra = extraPath, !extra.isEmpty {
            candidates.insert("\(name)/\(extra)", at: 0)
        }
        for candidate in candidates {
            if let found = list.first(where: { $0.name == candidate }) {
                return (found.name, found.sha)
            }
        }
        return nil
    }

    /// Tag → commit SHA, resolving annotated tags through `/git/tags`.
    func tagCommitSHA(owner: String, repo: String, tag: String) async throws -> String? {
        struct RefObject: Decodable { let sha: String; let type: String }
        struct GitRef: Decodable { let object: RefObject }
        struct TagObject: Decodable {
            let object: RefObject
            enum CodingKeys: String, CodingKey { case object }
        }
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        do {
            let ref: GitRef = try await get(path: "/repos/\(owner)/\(repo)/git/ref/tags/\(encoded)")
            if ref.object.type == "commit" { return ref.object.sha }
            // Annotated tag: peel to the commit.
            let peeled: TagObject = try await get(path: "/repos/\(owner)/\(repo)/git/tags/\(ref.object.sha)")
            return peeled.object.sha
        } catch GitHubError.http(let status, _) where status == 404 {
            return nil
        }
    }

    // MARK: - Plumbing

    private struct GitHubCommit: Decodable { let sha: String }

    private func request(path: String) throws -> URLRequest {
        guard let url = URL(string: Self.apiBase + path) else { throw GitHubError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CodeBerry-Lite/4.0", forHTTPHeaderField: "User-Agent")
        if let header = auth.authorizationHeader() {
            req.setValue(header, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func data(path: String) async throws -> (Data, URLResponse) {
        let req = try request(path: path)
        do {
            let (data, response) = try await session.data(for: req)
            try Self.checkRateLimit(response)
            try Self.checkStatus(data: data, response: response)
            return (data, response)
        } catch let e as URLError {
            if e.code == .cancelled { throw GitHubError.cancelled }
            throw GitHubError.network(e)
        }
    }

    private func get<T: Decodable>(path: String, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await data(path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding
        }
    }

    private func paged<T: Decodable>(path: String) async throws -> [T] {
        var out: [T] = []
        for page in 1...Self.maxPages {
            let batch: [T] = try await get(path: "\(path)?per_page=\(Self.perPage)&page=\(page)")
            out += batch
            if batch.count < Self.perPage { break }
        }
        return out
    }

    private static func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw GitHubError.unauthorized
        case 404:
            // Distinguish repo-not-found from other 404s by message sniffing
            // is unreliable; callers map to .notFound where appropriate.
            let msg = (try? JSONDecoder().decode(GitHubMessage.self, from: data))?.message ?? ""
            throw GitHubError.http(status: 404, message: msg)
        default:
            let msg = (try? JSONDecoder().decode(GitHubMessage.self, from: data))?.message ?? ""
            throw GitHubError.http(status: http.statusCode, message: msg)
        }
    }

    private struct GitHubMessage: Decodable { let message: String }

    private static func checkRateLimit(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 403 || http.statusCode == 429 {
            let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
            if remaining == "0" || http.statusCode == 429 {
                throw GitHubError.rateLimited(reset: try rateLimit(from: http).reset)
            }
        }
    }

    private static func rateLimit(from http: HTTPURLResponse) throws -> GitHubRateLimit {
        func int(_ name: String) -> Int {
            Int(http.value(forHTTPHeaderField: name) ?? "") ?? 0
        }
        let resetEpoch = Double(http.value(forHTTPHeaderField: "x-ratelimit-reset") ?? "") ?? 0
        return GitHubRateLimit(limit: int("x-ratelimit-limit"),
                               remaining: int("x-ratelimit-remaining"),
                               reset: Date(timeIntervalSince1970: resetEpoch))
    }
}
