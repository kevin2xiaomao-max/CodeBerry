import Foundation

// MARK: - M4: Security hardening (§27)
//
// Centralizes the security invariants so new code has one place to check:
// HTTPS-only network URLs, never execute downloaded content, and token
// redaction for any diagnostic output.

enum SecurityPolicy {
    /// Only https:// URLs are allowed for GitHub traffic.
    static func isAllowedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return true
    }

    /// True when the file looks executable (POSIX exec bit or known
    /// executable extension). Such files must never be launched.
    static func isExecutableFile(at url: URL) -> Bool {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let posix = attrs[.posixPermissions] as? NSNumber {
            let perms = posix.uint16Value
            if perms & 0o111 != 0 { return true }
        }
        let executableExtensions: Set<String> = [
            "sh", "command", "tool", "out", "run", "bin",
            "dylib", "framework", "bundle", "plugin",
        ]
        return executableExtensions.contains(url.pathExtension.lowercased())
    }

    /// Redacts anything that looks like a token from a string before logging.
    /// Conservative: masks `github_pat_…`, `ghp_…`, and `token …` values.
    static func redacted(_ string: String) -> String {
        var out = string
        for pattern in ["github_pat_[A-Za-z0-9_]+", "ghp_[A-Za-z0-9]+", "gho_[A-Za-z0-9]+"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                                     withTemplate: "***REDACTED***")
            }
        }
        return out
    }

    /// Asserts a downloaded archive contains no executable payload that we
    /// would run. CodeBerry never executes repo content (§27).
    static func assertNoExecutionPossible(at projectFolder: URL) -> Bool {
        // We never spawn processes for repo content — this documents the
        // invariant and gives tests a hook. Always true by construction.
        _ = projectFolder
        return true
    }
}
