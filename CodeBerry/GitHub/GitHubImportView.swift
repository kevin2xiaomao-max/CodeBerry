import SwiftUI

/// Import view model: URL → parse → repo info → ref pick → snapshot import.
@Observable
@MainActor
final class GitHubImportModel {
    var urlText = ""
    var parsed: GitHubRepoRef?
    var parseError: String?

    var repoInfo: GitHubRepoInfo?
    var branches: [GitHubBranch] = []
    var tags: [GitHubTag] = []
    var isLoadingRef = false
    var loadError: String?

    /// The ref the user chose (defaults from the parsed URL).
    var refKind: GitHubRefKind = .defaultBranch
    var selectedBranch = ""
    var selectedTag = ""
    var commitSHA = ""
    /// File to open after import (from a /blob/ URL).
    var fileToOpen: String?

    var importPhase: SnapshotSyncEngine.ImportPhase?
    var importError: String?

    var recent: [GitHubRecentRepo] = GitHubRecentStore.load()

    private let client: GitHubClient
    private let engine: SnapshotSyncEngine
    private let downloader = SnapshotDownloader()

    init() {
        let auth = GitHubTokenStore.currentAuth()
        self.client = GitHubClient(auth: auth)
        self.engine = SnapshotSyncEngine(client: client, downloader: downloader)
    }

    var canImport: Bool {
        parsed != nil && repoInfo != nil && !isLoadingRef && importPhase == nil
            && (refKind != .commit || !commitSHA.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Parse

    func parseURL() {
        parseError = nil
        repoInfo = nil
        branches = []
        tags = []
        loadError = nil
        fileToOpen = nil
        do {
            let p = try GitHubURLParser.parse(urlText)
            parsed = p
            // Default the ref picker from the URL. Repo-root URLs land on the
            // branch picker with the default branch filled in after load.
            switch p.refKind {
            case .defaultBranch:
                refKind = .branch
                selectedBranch = ""
            case .branch:
                refKind = .branch
                selectedBranch = p.refName ?? ""
                fileToOpen = p.filePath
            case .tag:
                refKind = .tag
                selectedTag = p.refName ?? ""
                fileToOpen = p.filePath
            case .commit:
                refKind = .commit
                commitSHA = p.refName ?? ""
            }
        } catch {
            parsed = nil
            parseError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if error is GitHubURLParserError {
                parseError = L10nService.shared.t(.errGithubInvalidURL)
            }
        }
    }

    // MARK: - Load repo info + refs

    func loadRepo() async {
        guard let parsed else { return }
        isLoadingRef = true
        loadError = nil
        defer { isLoadingRef = false }
        do {
            async let info = client.repoInfo(owner: parsed.owner, repo: parsed.repo)
            async let br = client.branches(owner: parsed.owner, repo: parsed.repo)
            async let tg = client.tags(owner: parsed.owner, repo: parsed.repo)
            let (i, b, t) = try await (info, br, tg)
            repoInfo = i
            branches = b
            tags = t
            // Disambiguate branch names containing slashes: the URL parser
            // splits `tree/feature/v3.6.1` into ref=`feature`, path=`v3.6.1`.
            if refKind == .branch, let extra = fileToOpen, !extra.isEmpty {
                let full = "\(selectedBranch)/\(extra)"
                if b.contains(where: { $0.name == full }) {
                    selectedBranch = full
                    fileToOpen = nil
                }
            }
            if selectedBranch.isEmpty { selectedBranch = i.defaultBranch }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Import

    /// Runs the import. Returns the project folder name on success.
    func runImport(workspaceRoot: URL) async -> String? {
        guard let parsed else { return nil }
        importError = nil
        importPhase = .downloading(-1)
        do {
            let ref = importRef(for: parsed)
            let resolved = try await client.resolve(ref)
            let folder = try await engine.importRepo(parsed: parsed, resolved: resolved,
                                                     workspaceRoot: workspaceRoot) { [weak self] phase in
                Task { @MainActor in self?.importPhase = phase }
            }
            importPhase = nil
            recent = GitHubRecentStore.load()
            return folder
        } catch {
            importPhase = nil
            if let gh = error as? GitHubError {
                importError = gh.errorDescription
            } else if let ex = error as? ArchiveExtractor.ExtractError {
                importError = ex.errorDescription
            } else {
                importError = error.localizedDescription
            }
            return nil
        }
    }

    func cancelImport() {
        downloader.cancel()
    }

    private func importRef(for parsed: GitHubRepoRef) -> GitHubRepoRef {
        switch refKind {
        case .defaultBranch:
            return GitHubRepoRef(owner: parsed.owner, repo: parsed.repo,
                                 refKind: .defaultBranch, refName: nil, filePath: nil)
        case .branch:
            let name = selectedBranch.isEmpty ? (repoInfo?.defaultBranch ?? "") : selectedBranch
            return GitHubRepoRef(owner: parsed.owner, repo: parsed.repo,
                                 refKind: .branch, refName: name, filePath: nil)
        case .tag:
            return GitHubRepoRef(owner: parsed.owner, repo: parsed.repo,
                                 refKind: .tag, refName: selectedTag, filePath: nil)
        case .commit:
            return GitHubRepoRef(owner: parsed.owner, repo: parsed.repo,
                                 refKind: .commit,
                                 refName: commitSHA.trimmingCharacters(in: .whitespacesAndNewlines),
                                 filePath: nil)
        }
    }
}

// MARK: - View

/// §8: paste a GitHub URL → pick a ref → import a snapshot as a project.
struct GitHubImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore
    @State private var model = GitHubImportModel()
    @Bindable private var l10n = L10nService.shared

    /// Called with the imported project folder name.
    var onImported: ((folder: String, openFile: String?)) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            List {
                Section(l10n.t(.githubURLLabel)) {
                    TextField(l10n.t(.githubURLPlaceholder), text: $model.urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.parseURL() }
                    Text(l10n.t(.githubParseHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let err = model.parseError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                if model.parsed != nil {
                    repoSection
                    refSection
                    importSection
                }

                if !model.recent.isEmpty {
                    Section(l10n.t(.githubRecentTitle)) {
                        ForEach(model.recent) { item in
                            Button {
                                model.urlText = "https://github.com/\(item.owner)/\(item.repo)"
                                model.parseURL()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.secondary)
                                    Text("\(item.owner)/\(item.repo)")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Section {
                        Text(l10n.t(.githubNoRecent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(l10n.t(.githubImportTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel)) { dismiss() }
                }
            }
            .onChange(of: model.urlText) { _, _ in model.parseURL() }
            .onChange(of: model.parsed) { _, newValue in
                if newValue != nil { Task { await model.loadRepo() } }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var repoSection: some View {
        Section(l10n.t(.githubRepoCard)) {
            if model.isLoadingRef && model.repoInfo == nil {
                ProgressView()
            } else if let info = model.repoInfo {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.fullName).font(.headline)
                        if let desc = info.description, !desc.isEmpty {
                            Text(desc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(info.isPrivate ? l10n.t(.githubPrivateBadge) : l10n.t(.githubPublicBadge))
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(info.isPrivate ? Color.orange.opacity(0.2) : Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            } else if let err = model.loadError {
                Text(err).font(.caption).foregroundStyle(.red)
                Button(l10n.t(.reload)) { Task { await model.loadRepo() } }
            }
        }
    }

    @ViewBuilder
    private var refSection: some View {
        Section(l10n.t(.githubRefSection)) {
            Picker(l10n.t(.githubRefSection), selection: $model.refKind) {
                Text(l10n.t(.githubRefBranch)).tag(GitHubRefKind.branch)
                Text(l10n.t(.githubRefTag)).tag(GitHubRefKind.tag)
                Text(l10n.t(.githubRefCommit)).tag(GitHubRefKind.commit)
            }
            .pickerStyle(.segmented)
            .disabled(model.isLoadingRef)

            switch model.refKind {
            case .defaultBranch, .branch:
                if model.isLoadingRef {
                    ProgressView()
                } else {
                    Picker(l10n.t(.githubRefBranch), selection: $model.selectedBranch) {
                        ForEach(model.branches) { b in
                            HStack {
                                Text(b.name)
                                if b.name == model.repoInfo?.defaultBranch {
                                    Text("· \(l10n.t(.githubDefaultBranchTag))")
                                        .foregroundStyle(.secondary)
                                }
                            }.tag(b.name)
                        }
                    }
                }
            case .tag:
                if model.isLoadingRef {
                    ProgressView()
                } else if model.tags.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Picker(l10n.t(.githubRefTag), selection: $model.selectedTag) {
                        ForEach(model.tags) { t in Text(t.name).tag(t.name) }
                    }
                    .onAppear {
                        if model.selectedTag.isEmpty { model.selectedTag = model.tags.first?.name ?? "" }
                    }
                }
            case .commit:
                TextField(l10n.t(.githubCommitSHAPlaceholder), text: $model.commitSHA)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            if let phase = model.importPhase {
                HStack {
                    ProgressView()
                    switch phase {
                    case .downloading(let p):
                        if p >= 0 {
                            Text("\(l10n.t(.githubDownloading)) \(Int(p * 100))%")
                        } else {
                            Text(l10n.t(.githubDownloading))
                        }
                    case .extracting:
                        Text(l10n.t(.githubExtracting))
                    case .done:
                        Text(l10n.t(.githubImportDone))
                    }
                    Spacer()
                    Button(l10n.t(.cancel)) { model.cancelImport() }
                }
            } else {
                Button(l10n.t(.githubImportAction)) {
                    Task {
                        let openFile = model.fileToOpen
                        if let folder = await model.runImport(workspaceRoot: store.rootURL) {
                            onImported((folder, openFile))
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canImport)
            }
            if let err = model.importError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
