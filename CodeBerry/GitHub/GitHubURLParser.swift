import Foundation

/// Which ref a GitHub URL points at. `.defaultBranch` means "resolve the
/// repo's default branch at import time".
enum GitHubRefKind: String, Codable, Equatable {
    case defaultBranch
    case branch
    case tag
    case commit
}

/// The parsed result of a GitHub repository URL (§8: 三种 URL 形态).
struct GitHubRepoRef: Equatable {
    let owner: String
    let repo: String
    let refKind: GitHubRefKind
    /// Branch/tag name, or full commit SHA. nil for `.defaultBranch`.
    let refName: String?
    /// File path inside the repo for `/blob/<ref>/<path>` URLs.
    /// M1 imports the whole repo snapshot and opens this file afterwards.
    let filePath: String?

    var displayRef: String {
        switch refKind {
        case .defaultBranch: return "default"
        case .branch, .tag: return refName ?? "?"
        case .commit: return refName.map { String($0.prefix(7)) } ?? "?"
        }
    }

    var slug: String { "\(owner)/\(repo)" }
}

enum GitHubURLParserError: Error, Equatable {
    case notGitHubURL
    case missingOwnerOrRepo
    case unsupportedForm
}

/// Parses the three supported GitHub URL forms (§8):
/// 1. `https://github.com/<owner>/<repo>` (`.git` suffix optional)
/// 2. `https://github.com/<owner>/<repo>/tree/<ref>[/<path>]`
/// 3. `https://github.com/<owner>/<repo>/blob/<ref>/<path>`
/// Plus SSH forms `git@github.com:<owner>/<repo>(.git)` and
/// `ssh://git@github.com/<owner>/<repo>(.git)` (repo root, default branch).
enum GitHubURLParser {
    static func parse(_ raw: String) throws -> GitHubRepoRef {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GitHubURLParserError.notGitHubURL }

        // SSH forms.
        if let ssh = parseSSH(text) { return ssh }

        guard let url = URL(string: text),
              let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") else {
            throw GitHubURLParserError.notGitHubURL
        }
        // Path components, dropping empty segments. `URL.pathComponents`
        // keeps a leading "/" element — filter it out.
        var parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count >= 2 else { throw GitHubURLParserError.missingOwnerOrRepo }

        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { throw GitHubURLParserError.missingOwnerOrRepo }
        parts.removeFirst(2)

        // Form 1: repo root.
        guard let form = parts.first else {
            return GitHubRepoRef(owner: owner, repo: repo,
                                refKind: .defaultBranch, refName: nil, filePath: nil)
        }
        guard parts.count >= 2 else { throw GitHubURLParserError.unsupportedForm }
        let ref = parts[1]
        let rest = Array(parts.dropFirst(2))
        switch form {
        case "tree":
            return GitHubRepoRef(owner: owner, repo: repo,
                                refKind: .branch, refName: ref,
                                filePath: rest.isEmpty ? nil : rest.joined(separator: "/"))
        case "blob":
            guard !rest.isEmpty else { throw GitHubURLParserError.unsupportedForm }
            return GitHubRepoRef(owner: owner, repo: repo,
                                refKind: .branch, refName: ref,
                                filePath: rest.joined(separator: "/"))
        case "commit", "commits":
            // `.../commit/<sha>` — treat as a commit ref.
            return GitHubRepoRef(owner: owner, repo: repo,
                                refKind: .commit, refName: ref, filePath: nil)
        default:
            throw GitHubURLParserError.unsupportedForm
        }
    }

    /// `git@github.com:owner/repo(.git)` and `ssh://git@github.com/owner/repo(.git)`.
    private static func parseSSH(_ text: String) -> GitHubRepoRef? {
        let stripped: String
        if text.hasPrefix("git@github.com:") {
            stripped = String(text.dropFirst("git@github.com:".count))
        } else if text.hasPrefix("ssh://git@github.com/") {
            stripped = String(text.dropFirst("ssh://git@github.com/".count))
        } else {
            return nil
        }
        var parts = stripped.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return GitHubRepoRef(owner: owner, repo: repo,
                            refKind: .defaultBranch, refName: nil, filePath: nil)
    }
}
