import SwiftUI

/// A command exposed through Quick Open (§M2: Quick Open — files / symbols /
/// commands). Commands are local actions; the parent injects handlers.
struct QuickCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String

    static func == (lhs: QuickCommand, rhs: QuickCommand) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Quick Open sheet: fuzzy-search files, symbols, and local commands.
struct QuickOpenView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case files, symbols, commands
        var id: String { rawValue }
        var title: String {
            switch self {
            case .files: return L10nService.shared.t(.quickOpenFiles)
            case .symbols: return L10nService.shared.t(.quickOpenSymbols)
            case .commands: return L10nService.shared.t(.quickOpenCommands)
            }
        }
    }

    @Binding var query: String
    @State var scope: Scope = .files
    @Bindable private var l10n = L10nService.shared
    let files: [String]
    let symbolIndex: SymbolIndex
    let commands: [QuickCommand]
    let onSelectFile: (String) -> Void
    let onSelectSymbol: (CodeSymbol) -> Void
    let onSelectCommand: (QuickCommand) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    switch scope {
                    case .files:
                        ForEach(matchedFiles, id: \.self) { file in
                            Button { onSelectFile(file) } label: {
                                Label(fileName(of: file), systemImage: "doc.text")
                            }
                        }
                    case .symbols:
                        ForEach(symbolIndex.symbols(matching: query)) { sym in
                            Button { onSelectSymbol(sym) } label: {
                                HStack {
                                    Image(systemName: sym.kind.iconName)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(sym.name).font(.body)
                                        Text(l10n.t(.symbolLineInfo, fileName(of: sym.filePath),
                                                         sym.kind.localizedName, sym.line))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    case .commands:
                        ForEach(matchedCommands) { cmd in
                            Button { onSelectCommand(cmd) } label: {
                                Label(cmd.title, systemImage: cmd.icon)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $query, prompt: l10n.t(.quickOpenSearchHint))
            .navigationTitle(l10n.t(.quickOpenTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel), action: onClose)
                }
            }
        }
    }

    private var matchedFiles: [String] {
        guard !query.isEmpty else { return Array(files.prefix(50)) }
        return files.compactMap { file -> (String, Int)? in
            guard let score = fuzzyScore(query: query, in: fileName(of: file)) else { return nil }
            return (file, score)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(50)
        .map(\.0)
    }

    private var matchedCommands: [QuickCommand] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func fileName(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

/// Subsequence fuzzy match shared by Quick Open (files) and SymbolIndex.
func fuzzyScore(query: String, in target: String) -> Int? {
    let q = Array(query.lowercased()), t = Array(target.lowercased())
    var ti = 0, score = 0, lastMatch = -2
    for qc in q {
        var found = false
        while ti < t.count {
            if t[ti] == qc {
                if ti == 0 { score -= 10 }
                if ti > lastMatch + 1 { score += (ti - lastMatch - 1) * 2 }
                lastMatch = ti
                ti += 1
                found = true
                break
            }
            ti += 1
        }
        if !found { return nil }
    }
    return score + t.count
}
