import Foundation
import Observation
import AgentKit

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

/// The on-device workspace: the same sandboxed folder the agent's file tools
/// operate on. Owns the navigator tree, open tabs, and the editor buffer.
@Observable
@MainActor
final class WorkspaceStore {
    let rootURL: URL
    private let workspace: Workspace

    private(set) var projects: [ProjectInfo] = []
    /// Folder name of the open project; nil shows the Projects home screen.
    private(set) var currentProject: String?
    private(set) var tree: [FileNode] = []
    var selectedPath: String?
    private(set) var openTabs: [String] = []
    private(set) var openFilePath: String?
    private(set) var isDirty = false
    var lastError: String?

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
        self.workspace = Workspace(root: rootURL)
        refresh()
        if projects.isEmpty { bootstrapWelcomeProject() }
        // Restore the last session: project first, then the open file.
        if let lastProject = UserDefaults.standard.string(forKey: Self.lastProjectKey),
           isDirectory(lastProject) {
            currentProject = lastProject
            refresh()
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
                // The project vanished (agent or Files app deleted it).
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
        UserDefaults.standard.set(name, forKey: Self.lastProjectKey)
    }

    func closeProject() {
        saveNowIfDirty()
        clearEditorState()
        currentProject = nil
        refresh()
        UserDefaults.standard.removeObject(forKey: Self.lastProjectKey)
    }

    /// Creates a project and navigates into it. `scaffold` builds a full,
    /// ready-to-build iOS app via AgentKit's project template (same one the
    /// agent's create_xcode_project tool uses); otherwise just a folder.
    func createProject(named rawName: String, scaffold: Bool) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if scaffold {
            // Module-safe name, matching the tool's own sanitizing.
            var name = trimmed.filter { $0.isLetter || $0.isNumber }
            if let first = name.first, first.isNumber { name = "App" + name }
            guard !name.isEmpty else {
                lastError = "Project name must contain letters or digits."
                return
            }
            do {
                _ = try await CreateXcodeProjectTool(workspace: workspace)
                    .execute(.object(["name": .string(name)]))
                refresh()
                openProject(name)
            } catch {
                lastError = error.localizedDescription
            }
        } else {
            guard !trimmed.contains("/") else {
                lastError = "Project names can't contain “/”."
                return
            }
            do {
                try FileManager.default.createDirectory(at: workspace.resolve(trimmed),
                                                        withIntermediateDirectories: true)
                refresh()
                openProject(trimmed)
            } catch {
                lastError = "Couldn't create project: \(error.localizedDescription)"
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
            lastError = "Can't open \(path) — not a UTF-8 text file."
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
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Create / delete / rename

    func createFile(named rawName: String, in folder: String?) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.contains(".") { name += ".swift" }
        let path = [folder, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        guard (try? workspace.read(path)) == nil else {
            lastError = "\(name) already exists."
            return
        }
        do {
            try workspace.write(path, content: Self.template(forFileNamed: name))
            refresh()
            openFile(path)
        } catch {
            lastError = "Couldn't create \(name): \(error.localizedDescription)"
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
            lastError = "Couldn't create folder: \(error.localizedDescription)"
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
            lastError = "Couldn't delete \(node.name): \(error.localizedDescription)"
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
            lastError = "Couldn't rename: \(error.localizedDescription)"
        }
    }

    // MARK: - Agent integration

    /// Called after the agent runs a tool: re-scan the tree and, if the open
    /// file changed on disk underneath a clean editor, reload it.
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
                        Text("Edit this file, or open the agent chat and ask it to build something.")
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
