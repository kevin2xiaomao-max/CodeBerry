import Foundation

// MARK: - M4: Session Restore
//
// Persists the workspace session (project, open file, per-file cursor line)
// and restores it on launch. Stored in UserDefaults — no secrets here.

/// Per-file cursor/scroll state.
struct FileSessionState: Codable, Equatable {
    /// 1-based line number.
    var line: Int
}

/// The persisted session.
struct WorkspaceSession: Codable, Equatable {
    /// Absolute project folder path (nil = no project open).
    var projectFolder: String?
    /// Workspace-relative path of the open file.
    var openFilePath: String?
    /// Cursor line per workspace-relative path.
    var cursorLines: [String: Int]
    /// Selected bottom-tab (0=files, 1=code, 2=preview, 3=changes).
    var selectedTab: Int

    static let empty = WorkspaceSession(
        projectFolder: nil, openFilePath: nil, cursorLines: [:], selectedTab: 0)
}

/// Save/restore for the workspace session.
enum SessionStore {
    private static let key = "codeberry.workspaceSession.v1"

    static func save(_ session: WorkspaceSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> WorkspaceSession {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? JSONDecoder().decode(WorkspaceSession.self, from: data) else {
            return .empty
        }
        return session
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
