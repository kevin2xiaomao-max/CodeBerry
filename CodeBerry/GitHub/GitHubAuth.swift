import Foundation

/// How API/download requests authenticate (§8: public 直连 / PAT).
/// PATs live in the Keychain only — never UserDefaults, never source.
protocol GitHubAuthProvider {
    /// Value for the `Authorization` header, or nil for anonymous.
    func authorizationHeader() -> String?
    var isAuthenticated: Bool { get }
}

/// No token: public repos only, 60 req/hour.
struct AnonymousGitHubAuth: GitHubAuthProvider {
    func authorizationHeader() -> String? { nil }
    var isAuthenticated: Bool { false }
}

/// Personal Access Token (classic `ghp_…` or fine-grained `github_pat_…`).
struct TokenGitHubAuth: GitHubAuthProvider {
    let token: String
    func authorizationHeader() -> String? { "Bearer \(token)" }
    var isAuthenticated: Bool { true }
}

/// Keychain-backed PAT storage (§8, §11: 凭据只进 Keychain).
enum GitHubTokenStore {
    private static let keychainKey = "github.pat"

    static var hasToken: Bool { (try? load()) != nil }

    static func load() throws -> String {
        guard let token = KeychainStore.load(key: keychainKey),
              !token.isEmpty else {
            throw GitHubTokenError.noToken
        }
        return token
    }

    static func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitHubTokenError.emptyToken }
        guard trimmed.hasPrefix("ghp_") || trimmed.hasPrefix("github_pat_")
                || trimmed.hasPrefix("gho_") || trimmed.hasPrefix("ghu_") else {
            throw GitHubTokenError.unrecognizedFormat
        }
        KeychainStore.save(key: keychainKey, value: trimmed)
    }

    static func delete() {
        KeychainStore.delete(key: keychainKey)
    }

    /// The auth provider to use for a request: token when set, else anonymous.
    static func currentAuth() -> GitHubAuthProvider {
        if let token = KeychainStore.load(key: keychainKey), !token.isEmpty {
            return TokenGitHubAuth(token: token)
        }
        return AnonymousGitHubAuth()
    }
}

enum GitHubTokenError: Error, LocalizedError {
    case noToken
    case emptyToken
    case unrecognizedFormat

    var errorDescription: String? {
        L10nService.shared.t(key)
    }

    private var key: L10nKey {
        switch self {
        case .noToken: return .errGithubNoToken
        case .emptyToken: return .errGithubTokenEmpty
        case .unrecognizedFormat: return .errGithubTokenFormat
        }
    }
}
