import SwiftUI

/// Home screen: every top-level workspace folder is a project. Tapping one
/// opens the file navigator; "+" scaffolds a new one.
struct ProjectsListView: View {
    @Bindable var store: WorkspaceStore
    var onShowSettings: () -> Void

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var renameTarget: ProjectInfo?
    @State private var renameText = ""
    @State private var deleteTarget: ProjectInfo?
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        Group {
            if store.projects.isEmpty {
                ContentUnavailableView {
                    Label(l10n.t(.noProjects), systemImage: "folder.badge.plus")
                } description: {
                    Text(l10n.t(.noProjectsDesc))
                } actions: {
                    Button(l10n.t(.newProject)) {
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
                    Button(l10n.t(.settings), systemImage: "gearshape") {
                        onShowSettings()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
        .alert(l10n.t(.newProject), isPresented: $showNewProject) {
            TextField(l10n.t(.projectNamePlaceholder), text: $newProjectName)
                .textInputAutocapitalization(.never)
            Button(l10n.t(.createAppProject)) {
                let name = newProjectName
                Task { await store.createProject(named: name, scaffold: true) }
            }
            Button(l10n.t(.createEmptyProject)) {
                let name = newProjectName
                Task { await store.createProject(named: name, scaffold: false) }
            }
            Button(l10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(l10n.t(.newProjectMessage))
        }
        .alert(l10n.t(.renameProject), isPresented: Binding(get: { renameTarget != nil },
                                                      set: { if !$0 { renameTarget = nil } })) {
            TextField(l10n.t(.newNamePlaceholder), text: $renameText)
                .textInputAutocapitalization(.never)
            Button(l10n.t(.rename)) {
                if let target = renameTarget { store.rename(node(for: target), to: renameText) }
                renameTarget = nil
            }
            Button(l10n.t(.cancel), role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(l10n.t(.delete) + " \(deleteTarget?.name ?? "")?",
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button(l10n.t(.delete), role: .destructive) {
                if let target = deleteTarget { store.delete(node(for: target)) }
                deleteTarget = nil
            }
            Button(l10n.t(.cancel), role: .cancel) { deleteTarget = nil }
        } message: {
            Text(l10n.t(.deleteProjectMessage))
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
            Button(l10n.t(.rename), systemImage: "pencil") {
                renameTarget = project
                renameText = project.name
            }
            Button(l10n.t(.delete), systemImage: "trash", role: .destructive) {
                deleteTarget = project
            }
        }
        .swipeActions(edge: .trailing) {
            Button(l10n.t(.delete), systemImage: "trash", role: .destructive) {
                deleteTarget = project
            }
        }
    }

    private func caption(for project: ProjectInfo) -> String {
        var parts = [project.isAppProject ? l10n.t(.iosAppKind) : l10n.t(.folderKind)]
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
