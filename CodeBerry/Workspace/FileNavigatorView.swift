import SwiftUI

/// Xcode-style project navigator: file tree with create / rename / delete.
struct FileNavigatorView: View {
    @Bindable var store: WorkspaceStore
    var onBackToProjects: () -> Void

    @State private var showNewFile = false
    @State private var newFileName = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: FileNode?
    @State private var renameText = ""
    @State private var deleteTarget: FileNode?
    @State private var expandedFolders: Set<String> = []
    /// Folder targeted by a context-menu "New File/Folder"; nil = use selection.
    @State private var newItemFolder: String?

    var body: some View {
        List(selection: $store.selectedPath) {
            if store.tree.isEmpty {
                ContentUnavailableView("Empty Workspace",
                                       systemImage: "folder",
                                       description: Text("Create a Swift file with + or ask the agent to build something."))
            } else {
                outline(store.tree)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(store.currentProject ?? "CodeBerry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBackToProjects()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Projects")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Swift File", systemImage: "doc.badge.plus") {
                        newItemFolder = nil
                        newFileName = ""
                        showNewFile = true
                    }
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        newItemFolder = nil
                        newFolderName = ""
                        showNewFolder = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Swift File", isPresented: $showNewFile) {
            TextField("Name, e.g. TimerView.swift", text: $newFileName)
                .textInputAutocapitalization(.never)
            Button("Create") {
                if let folder = destinationFolder { expandedFolders.insert(folder) }
                store.createFile(named: newFileName, in: destinationFolder)
                newItemFolder = nil
            }
            Button("Cancel", role: .cancel) { newItemFolder = nil }
        } message: {
            Text("Created in \(destinationFolder?.isEmpty == false ? destinationFolder! : "the workspace root").")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
                .textInputAutocapitalization(.never)
            Button("Create") {
                if let folder = destinationFolder { expandedFolders.insert(folder) }
                store.createFolder(named: newFolderName, in: destinationFolder)
                newItemFolder = nil
            }
            Button("Cancel", role: .cancel) { newItemFolder = nil }
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil },
                                              set: { if !$0 { renameTarget = nil } })) {
            TextField("New name", text: $renameText)
                .textInputAutocapitalization(.never)
            Button("Rename") {
                if let target = renameTarget { store.rename(target, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog("Delete \(deleteTarget?.name ?? "")?",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { store.delete(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Recursive tree. Folders are DisclosureGroups whose whole row toggles
    /// expansion on tap and never becomes the List selection (which would
    /// navigate to the editor on iPhone); only files are selectable.
    @ViewBuilder
    private func outline(_ nodes: [FileNode]) -> some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansionBinding(node.path)) {
                    AnyView(outline(children))
                } label: {
                    row(for: node)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) { toggleExpansion(node.path) }
                        }
                }
                .selectionDisabled()
            } else {
                row(for: node)
                    .tag(node.path)
                    .selectionDisabled(node.isDirectory)   // .xcodeproj leaves
            }
        }
    }

    private func expansionBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { expandedFolders.contains(path) },
                set: { isExpanded in
                    if isExpanded { expandedFolders.insert(path) }
                    else { expandedFolders.remove(path) }
                })
    }

    private func toggleExpansion(_ path: String) {
        if expandedFolders.contains(path) { expandedFolders.remove(path) }
        else { expandedFolders.insert(path) }
    }

    private func row(for node: FileNode) -> some View {
        Label {
            Text(node.name)
                .lineLimit(1)
        } icon: {
            icon(for: node)
        }
        .contextMenu {
            if node.isDirectory && !node.isXcodeProject {
                Button("New Swift File", systemImage: "doc.badge.plus") {
                    newItemFolder = node.path
                    newFileName = ""
                    showNewFile = true
                }
                Button("New Folder", systemImage: "folder.badge.plus") {
                    newItemFolder = node.path
                    newFolderName = ""
                    showNewFolder = true
                }
                Divider()
            }
            Button("Rename", systemImage: "pencil") {
                renameTarget = node
                renameText = node.name
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = node
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = node
            }
        }
    }

    private func icon(for node: FileNode) -> some View {
        let (symbol, color): (String, Color) = {
            if node.isXcodeProject { return ("hammer.fill", .blue) }
            if node.isDirectory { return ("folder.fill", Color(red: 0.35, green: 0.65, blue: 1.0)) }
            switch (node.name as NSString).pathExtension.lowercased() {
            case "swift": return ("swift", .orange)
            case "json", "plist": return ("curlybraces", .secondary)
            case "md", "txt": return ("doc.text", .secondary)
            default: return ("doc", .secondary)
            }
        }()
        return Image(systemName: symbol).foregroundStyle(color)
    }

    /// Context-menu target folder if set, else next to the selected file,
    /// else the project root.
    private var destinationFolder: String? {
        if let newItemFolder { return newItemFolder }
        guard let sel = store.selectedPath else { return store.currentProject }
        let parent = (sel as NSString).deletingLastPathComponent
        return parent.isEmpty ? store.currentProject : parent
    }
}
