import SwiftUI

/// Project-wide text search UI (§M2: Project Search).
struct ProjectSearchView: View {
    @State var query: String = ""
    @State private var caseSensitive = false
    @State private var results: [ProjectSearchResult] = []
    @State private var isSearching = false
    let projectRoot: URL?
    let onSelect: (ProjectSearchResult) -> Void
    let onClose: () -> Void
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Toggle(l10n.t(.projectSearchCase), isOn: $caseSensitive)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                Divider()
                Group {
                    if isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search
                    } else {
                        List(results) { hit in
                            Button { onSelect(hit) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.lineText)
                                        .font(.system(.callout, design: .monospaced))
                                        .lineLimit(2)
                                    Text(l10n.t(.symbolLineInfo,
                                                 (hit.filePath as NSString).lastPathComponent,
                                                 hit.filePath, hit.line))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: l10n.t(.projectSearchHint))
            .onChange(of: query) { _, _ in scheduleSearch() }
            .onChange(of: caseSensitive) { _, _ in scheduleSearch() }
            .navigationTitle(l10n.t(.projectSearchTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel), action: onClose)
                }
            }
        }
    }

    @State private var searchTask: Task<Void, Never>?

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query
        let cs = caseSensitive
        guard !q.isEmpty, let root = projectRoot else {
            results = []
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let hits = await Task.detached {
                ProjectSearch.search(projectRoot: root, query: q, caseSensitive: cs)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = hits
                isSearching = false
            }
        }
    }
}
