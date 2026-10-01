import Foundation
import Observation

/// One entry in the file navigator tree. `children == nil` means leaf.
struct FileNode: Identifiable, Hashable {
    let path: String          // relative to the workspace root
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var id: String { path }

    var isXcodeProject: Bool { name.hasSuffix(".xcodeproj") }
}

/// A top-level folder in the workspace, shown on the Projects home screen.
struct ProjectInfo: Identifiable {
    let name: String
    /// True when the folder contains a `<name>.xcodeproj` scaffold.
    let isAppProject: Bool
    let modified: Date?
    var id: String { name }
}

/// The on-device workspace: the app's sandboxed Documents folder.
/// Owns the navigator tree, open tabs, and the editor buffer.
@Observable
@MainActor
final class WorkspaceStore {
    let rootURL: URL
    private let workspace: LiteWorkspace

    private(set) var projects: [ProjectInfo] = []
    /// Folder name of the open project; nil shows the Projects home screen.
    private(set) var currentProject: String?
    private(set) var tree: [FileNode] = []
    var selectedPath: String?
    private(set) var openTabs: [String] = []
    private(set) var openFilePath: String?
    /// Pending Preview → Code line jump (P1-1). Set when FourTabView handles
    /// `.codeBerryJumpToCode`; consumed by EditorPaneView.
    private(set) var pendingLineJump: Int?

    /// Requests a line jump in the open file. Consumed by EditorPaneView.
    func requestLineJump(_ line: Int) { pendingLineJump = line }

    /// Consumes the pending line jump, if any.
    func consumeLineJump() -> Int? {
        defer { pendingLineJump = nil }
        return pendingLineJump
    }
    private(set) var isDirty = false
    var lastError: String?
    /// Project-wide Swift symbol index (M2: Quick Open / completion /
    /// Jump to Definition). Rebuilt on project open, updated on save.
    let symbolIndex = SymbolIndex()

    // MARK: - M4.1 GitHub sync orchestration (P0-2)
    /// GitHub metadata for the open project; nil for non-GitHub projects.
    private(set) var githubMetadata: GitHubRepoMetadata?
    /// Unresolved conflicts from the last applied sync.
    private(set) var syncConflicts: [GitHubSyncConflict] = []
    /// Retained while a sync plan is pending or conflicts are unresolved,
    /// so "Use Remote" can copy remote content without re-downloading.
    var pendingSyncPlan: GitHubSyncPlan?
    var pendingSyncStaging: URL?
    var pendingRemoteManifest: [String: String] = [:]
    private(set) var isSyncing = false
    var syncError: String?
    var syncNotice: String?
    var syncEngine: SnapshotSyncEngine?
    let syncDownloader = SnapshotDownloader()

    var editorText = "" {
        didSet {
            guard !isLoadingFile, openFilePath != nil, editorText != oldValue else { return }
            isDirty = true
            scheduleAutosave()
        }
    }

    private var isLoadingFile = false
    private var autosaveTask: Task<Void, Never>?

    init(rootURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.rootURL = rootURL
        self.workspace = LiteWorkspace(root: rootURL)
        refresh()
        if projects.isEmpty { bootstrapWelcomeProject() }
        // Restore the last session: project first, then the open file.
        if let lastProject = UserDefaults.standard.string(forKey: Self.lastProjectKey),
           isDirectory(lastProject) {
            currentProject = lastProject
            refresh()
            rebuildSymbolIndex()
            analyzeProject()
            refreshGitHubState()
            if let lastFile = UserDefaults.standard.string(forKey: Self.lastOpenFileKey),
               lastFile.hasPrefix(lastProject + "/") {
                openFile(lastFile)
            }
        }
    }

    private static let lastOpenFileKey = "lastOpenFilePath"
    private static let lastProjectKey = "lastProjectPath"

    var openFileName: String? { openFilePath.map { ($0 as NSString).lastPathComponent } }

    // MARK: - Projects

    func refresh() {
        projects = loadProjects()
        if let current = currentProject {
            if isDirectory(current), let url = try? workspace.resolve(current) {
                tree = nodes(in: url, relativePath: current)
            } else {
                // The project vanished (deleted via the Files app).
                currentProject = nil
                tree = []
            }
        } else {
            tree = []
        }
    }

    private func loadProjects() -> [ProjectInfo] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return items.compactMap { url -> ProjectInfo? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { return nil }
            let name = url.lastPathComponent
            guard !name.hasSuffix(".xcodeproj") else { return nil }
            let hasXcodeproj = fm.fileExists(atPath: url.appendingPathComponent("\(name).xcodeproj").path)
            return ProjectInfo(name: name, isAppProject: hasXcodeproj, modified: values?.contentModificationDate)
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    func openProject(_ name: String) {
        guard name != currentProject else { return }
        saveNowIfDirty()
        clearEditorState()
        currentProject = name
        refresh()
        rebuildSymbolIndex()
        analyzeProject()
        refreshGitHubState()
        // P0-1: entering a workspace persists the session, so killing the
        // app mid-workspace restores back into it.
        saveSession()
        UserDefaults.standard.set(name, forKey: Self.lastProjectKey)
    }

    func closeProject() {
        saveNowIfDirty()
        clearEditorState()
        currentProject = nil
        refresh()
        refreshGitHubState()
        // P0-1: Back to Projects persists the exit — a relaunch stays on
        // Projects instead of restore-locking the user back in.
        SessionStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.lastProjectKey)
    }

    /// Creates a project and navigates into it. `scaffold` creates the
    /// project folder with a starter SwiftUI file; otherwise just a folder.
    /// (Lite build: the full .xcodeproj template lives in AgentKit, which
    /// is not part of this build.)
    func createProject(named rawName: String, scaffold: Bool) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if scaffold {
            // Module-safe name.
            var name = trimmed.filter { $0.isLetter || $0.isNumber }
            if let first = name.first, first.isNumber { name = "App" + name }
            guard !name.isEmpty else {
                lastError = L10nService.shared.t(.errProjectNameInvalid)
                return
            }
            do {
                try FileManager.default.createDirectory(at: workspace.resolve(name),
                                                        withIntermediateDirectories: true)
                try workspace.write("\(name)/ContentView.swift",
                                    content: Self.template(forFileNamed: "ContentView.swift"))
                refresh()
                openProject(name)
            } catch {
                lastError = L10nService.shared.t(.errCreateProject, error.localizedDescription)
            }
        } else {
            guard !trimmed.contains("/") else {
                lastError = L10nService.shared.t(.errProjectNameSlash)
                return
            }
            do {
                try FileManager.default.createDirectory(at: workspace.resolve(trimmed),
                                                        withIntermediateDirectories: true)
                refresh()
                openProject(trimmed)
            } catch {
                lastError = L10nService.shared.t(.errCreateProject, error.localizedDescription)
            }
        }
    }

    private func clearEditorState() {
        openTabs = []
        openFilePath = nil
        isLoadingFile = true
        editorText = ""
        isLoadingFile = false
        isDirty = false
        selectedPath = nil
    }

    // MARK: - Tree

    private func nodes(in dir: URL, relativePath: String) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [FileNode] = []
        for url in items {
            let name = url.lastPathComponent
            if name == ".DS_Store" { continue }
            let rel = relativePath.isEmpty ? name : relativePath + "/" + name
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if name.hasSuffix(".xcodeproj") {
                    // Shown as a leaf, like Xcode's blue project icon. Not editable.
                    out.append(FileNode(path: rel, name: name, isDirectory: true, children: nil))
                } else {
                    out.append(FileNode(path: rel, name: name, isDirectory: true,
                                        children: nodes(in: url, relativePath: rel)))
                }
            } else {
                out.append(FileNode(path: rel, name: name, isDirectory: false, children: nil))
            }
        }
        return out.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func isDirectory(_ path: String) -> Bool {
        guard let url = try? workspace.resolve(path) else { return false }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    // MARK: - Open / close / save

    // MARK: - M4: Session restore

    /// Persists the current session (project, open file, cursor lines).
    func saveSession(selectedTab: Int = 0) {
        // Cursor lines are recorded by the editor (M5 wires per-file tracking).
        let session = WorkspaceSession(
            projectFolder: currentProject,
            openFilePath: openFilePath,
            cursorLines: [:],
            selectedTab: selectedTab)
        SessionStore.save(session)
    }

    /// Returns the persisted session for restore-on-launch (M5 wires the UI).
    func loadSession() -> WorkspaceSession { SessionStore.load() }

    /// M5: restores the last session on launch (project + open file).
    /// Safe to call once at startup; no-ops if the project is gone.
    func restoreSession() {
        let session = SessionStore.load()
        guard let folder = session.projectFolder, !folder.isEmpty else { return }
        let url = rootURL.appendingPathComponent(folder)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        openProject(folder)
        if let openFile = session.openFilePath, !openFile.isEmpty {
            // openFilePath is stored as a full workspace path.
            self.openFile(openFile)
        }
    }

    func openFile(_ path: String) {
        guard path != openFilePath else { return }
        guard !isDirectory(path) else { return }
        saveNowIfDirty()
        do {
            let content = try workspace.read(path)
            isLoadingFile = true
            openFilePath = path
            editorText = content
            isLoadingFile = false
            isDirty = false
            if !openTabs.contains(path) { openTabs.append(path) }
            selectedPath = path
            lastError = nil
            UserDefaults.standard.set(path, forKey: Self.lastOpenFileKey)
        } catch {
            lastError = L10nService.shared.t(.errOpenNotUTF8, path)
        }
    }

    func closeTab(_ path: String) {
        if path == openFilePath { saveNowIfDirty() }
        openTabs.removeAll { $0 == path }
        guard openFilePath == path else { return }
        openFilePath = nil
        isLoadingFile = true
        editorText = ""
        isLoadingFile = false
        isDirty = false
        if let next = openTabs.last { openFile(next) }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNowIfDirty()
        }
    }

    func saveNowIfDirty() {
        guard isDirty, let path = openFilePath else { return }
        do {
            try workspace.write(path, content: editorText)
            isDirty = false
            // M4: record a local-history revision on every successful save.
            LocalHistoryStore.shared.record(path: path, content: editorText)
            if path.hasSuffix(".swift"), let rel = projectRelativePath(of: path) {
                symbolIndex.updateFile(relativePath: rel, content: editorText)
            }
        } catch {
            lastError = L10nService.shared.t(.errSaveFailed, error.localizedDescription)
        }
    }

    // MARK: - M2: Symbol index / Quick Open / navigation

    /// Project-relative path for a workspace-relative path, e.g.
    /// "MyApp/Sources/A.swift" -> "Sources/A.swift".
    func projectRelativePath(of workspacePath: String) -> String? {
        guard let project = currentProject else { return nil }
        let prefix = project + "/"
        guard workspacePath.hasPrefix(prefix) else { return nil }
        return String(workspacePath.dropFirst(prefix.count))
    }

    /// Workspace-relative path for a project-relative path.
    func workspacePath(ofProjectRelative relative: String) -> String? {
        guard let project = currentProject else { return nil }
        return project + "/" + relative
    }

    /// Full rebuild of the symbol index over the open project.
    func rebuildSymbolIndex() {
        guard let root = previewProjectRoot() else { return }
        symbolIndex.rebuild(projectRoot: root)
    }

    // MARK: - M3 §8 ProjectAnalyzer

    /// Ranked previewable pages for the open project (built in background).
    var projectAnalysis: ProjectAnalysis?
    private var analysisTask: Task<Void, Never>?

    /// Rebuild the preview-candidates ranking off the main thread.
    func analyzeProject() {
        analysisTask?.cancel()
        guard let root = previewProjectRoot() else { projectAnalysis = nil; return }
        analysisTask = Task.detached(priority: .utility) { [weak self] in
            let analysis = ProjectAnalyzer.analyze(root: root)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.projectAnalysis = analysis }
        }
    }

    /// All files in the open project, project-relative (Quick Open).
    func allProjectFiles() -> [String] {
        guard let root = previewProjectRoot() else { return [] }
        var out: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            out.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
        }
        return out.sorted()
    }

    /// Current contents of every .swift file (editor buffer wins for the
    /// open file). Used by Find References.
    func swiftFileContents() -> [String: String] {
        guard let root = previewProjectRoot() else { return [:] }
        var out: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [:] }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if let wsPath = workspacePath(ofProjectRelative: relative), wsPath == openFilePath {
                out[relative] = editorText
            } else if let content = try? String(contentsOf: url, encoding: .utf8) {
                out[relative] = content
            }
        }
        return out
    }

    // MARK: - Preview support (§二 multi-file index, §三 inspector writes)

    /// The opened project's folder URL, for the preview index.
    func previewProjectRoot() -> URL? {
        guard let name = currentProject else { return nil }
        return try? workspace.resolve(name)
    }

    /// File content for the preview index: the editor buffer wins for the
    /// open file ("当前文件的定义优先"), disk for everything else.
    func previewFileContent(_ path: String) -> String? {
        if path == openFilePath { return editorText }
        return try? workspace.read(path)
    }

    /// Write a file from the Inspector (§三: only after the user confirms the
    /// diff; §十三: a failed write keeps the original file).
    @discardableResult
    func writePreviewFile(_ path: String, content: String) -> Bool {
        do {
            try workspace.write(path, content: content)
            if path == openFilePath {
                editorText = content
                isDirty = false
            }
            refresh()
            return true
        } catch {
            lastError = L10nService.shared.t(.errSaveFailed, error.localizedDescription)
            return false
        }
    }

    // MARK: - Create / delete / rename

    func createFile(named rawName: String, in folder: String?) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.contains(".") { name += ".swift" }
        let path = [folder, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        guard (try? workspace.read(path)) == nil else {
            lastError = L10nService.shared.t(.errFileExists, name)
            return
        }
        do {
            try workspace.write(path, content: Self.template(forFileNamed: name))
            refresh()
            openFile(path)
        } catch {
            lastError = L10nService.shared.t(.errCreateFile, name, error.localizedDescription)
        }
    }

    func createFolder(named rawName: String, in folder: String?) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let path = [folder, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        do {
            try FileManager.default.createDirectory(at: workspace.resolve(path),
                                                    withIntermediateDirectories: true)
            refresh()
        } catch {
            lastError = L10nService.shared.t(.errCreateFolder, error.localizedDescription)
        }
    }

    func delete(_ node: FileNode) {
        do {
            try FileManager.default.removeItem(at: workspace.resolve(node.path))
            for tab in openTabs where tab == node.path || tab.hasPrefix(node.path + "/") {
                closeTab(tab)
            }
            if selectedPath == node.path { selectedPath = nil }
            refresh()
        } catch {
            lastError = L10nService.shared.t(.errDeleteFailed, node.name, error.localizedDescription)
        }
    }

    func rename(_ node: FileNode, to rawNewName: String) {
        var newName = rawNewName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != node.name else { return }
        if !node.isDirectory, !newName.contains(".") {
            newName += (node.name as NSString).pathExtension.isEmpty ? "" : "." + (node.name as NSString).pathExtension
        }
        let parent = (node.path as NSString).deletingLastPathComponent
        let newPath = parent.isEmpty ? newName : parent + "/" + newName
        do {
            try FileManager.default.moveItem(at: workspace.resolve(node.path),
                                             to: workspace.resolve(newPath))
            if openFilePath == node.path { openFilePath = newPath }
            openTabs = openTabs.map { tab in
                if tab == node.path { return newPath }
                if tab.hasPrefix(node.path + "/") { return newPath + tab.dropFirst(node.path.count) }
                return tab
            }
            if selectedPath == node.path { selectedPath = newPath }
            refresh()
        } catch {
            lastError = L10nService.shared.t(.errRenameFailed, error.localizedDescription)
        }
    }

    // MARK: - External changes

    /// Re-scan the tree and, if the open file changed on disk underneath a
    /// clean editor (e.g. via the Files app), reload it.
    func handleAgentMutation() {
        refresh()
        guard let path = openFilePath else { return }
        guard let disk = try? workspace.read(path) else {
            // The agent deleted the open file.
            closeTab(path)
            return
        }
        if !isDirty, disk != editorText {
            isLoadingFile = true
            editorText = disk
            isLoadingFile = false
        }
    }

    // MARK: - Templates

    private func bootstrapWelcomeProject() {
        try? workspace.write("Welcome/Welcome.swift",
                             content: Self.template(forFileNamed: "Welcome.swift"))
        refresh()
    }

    static func template(forFileNamed name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let date = Date.now.formatted(date: .abbreviated, time: .omitted)
        let header = """
        //
        //  \(name)
        //  CodeBerry Workspace
        //
        //  Created on \(date).
        //

        """
        guard name.hasSuffix(".swift") else { return "" }
        if base.hasSuffix("View") || base == "Welcome" {
            let typeName = base == "Welcome" ? "WelcomeView" : base
            return header + """
            import SwiftUI

            struct \(typeName): View {
                var body: some View {
                    VStack(spacing: 12) {
                        Image(systemName: "swift")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Hello, CodeBerry!")
                            .font(.title.bold())
                        Text("Edit this file, or create a new file to keep building.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }

            #Preview {
                \(typeName)()
            }
            """
        }
        return header + "import Foundation\n"
    }
}
