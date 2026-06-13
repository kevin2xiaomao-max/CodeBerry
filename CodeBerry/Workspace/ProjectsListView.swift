import SwiftUI

/// Home screen: every top-level workspace folder is a project. Tapping one
/// opens the file navigator; "+" scaffolds a new one.
struct ProjectsListView: View {
    @Bindable var store: WorkspaceStore
    var onShowSettings: () -> Void
    var onToggleChat: () -> Void

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var renameTarget: ProjectInfo?
    @State private var renameText = ""
    @State private var deleteTarget: ProjectInfo?

    var body: some View {
        Group {
            if store.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder.badge.plus")
                } description: {
                    Text("Create your first project to start coding, or ask the agent to build one.")
                } actions: {
                    Button("New Project") {
                        newProjectName = ""
                        showNewProject = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(store.projects) { project in
                        row(for: project)
                    }
                }
            }
        }
        .navigationTitle("CodeBerry")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Settings", systemImage: "gearshape") {
                        onShowSettings()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onToggleChat()
                } label: {
                    Image(systemName: "sparkles")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newProjectName = ""
                    showNewProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Project", isPresented: $showNewProject) {
            TextField("Name, e.g. PomodoroTimer", text: $newProjectName)
                .textInputAutocapitalization(.never)
            Button("Create App Project") {
                let name = newProjectName
                Task { await store.createProject(named: name, scaffold: true) }
            }
            Button("Create Empty Project") {
                let name = newProjectName
                Task { await store.createProject(named: name, scaffold: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("App projects include a ready-to-build .xcodeproj scaffold; empty projects are just a folder.")
        }
        .alert("Rename Project", isPresented: Binding(get: { renameTarget != nil },
                                                      set: { if !$0 { renameTarget = nil } })) {
            TextField("New name", text: $renameText)
                .textInputAutocapitalization(.never)
            Button("Rename") {
                if let target = renameTarget { store.rename(node(for: target), to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog("Delete \(deleteTarget?.name ?? "")?",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { store.delete(node(for: target)) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This deletes the whole project folder and can't be undone.")
        }
    }

    private func row(for project: ProjectInfo) -> some View {
        Button {
            store.openProject(project.name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(project.isAppProject
                              ? AnyShapeStyle(Color.blue.gradient)
                              : AnyShapeStyle(Color.gray.gradient))
                    Image(systemName: project.isAppProject ? "hammer.fill" : "folder.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(caption(for: project))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameTarget = project
                renameText = project.name
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = project
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = project
            }
        }
    }

    private func caption(for project: ProjectInfo) -> String {
        var parts = [project.isAppProject ? "iOS App" : "Folder"]
        if let modified = project.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    /// Project rows reuse the store's FileNode-based rename/delete.
    private func node(for project: ProjectInfo) -> FileNode {
        FileNode(path: project.name, name: project.name, isDirectory: true, children: nil)
    }
}
