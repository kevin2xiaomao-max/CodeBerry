import Foundation
import SwiftUI

/// Jump to Definition / Find References (§M2), powered by SymbolIndex.
/// Pure navigation logic lives here; WorkspaceStore performs the actual
/// file opening (M4 wires the "更改" tab into the same path).
enum CodeNavigation {
    /// The identifier under the caret, if any.
    static func identifier(at caret: Int, in text: String) -> String? {
        let ns = text as NSString
        guard caret <= ns.length else { return nil }
        var start = caret
        while start > 0, isIdent(ns.character(at: start - 1)) { start -= 1 }
        var end = caret
        while end < ns.length, isIdent(ns.character(at: end)) { end += 1 }
        guard end > start else { return nil }
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isIdent(_ c: unichar) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95
    }
}

/// One Find References hit.
struct ReferenceHit: Hashable {
    let filePath: String
    let line: Int
}

/// Find References result list.
struct ReferencesListView: View {
    let symbolName: String
    let results: [ReferenceHit]
    let onSelect: (String, Int) -> Void
    let onClose: () -> Void
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.t(.referencesEmpty), systemImage: "magnifyingglass")
                    } description: {
                        Text(l10n.t(.referencesEmptyDesc, symbolName))
                    }
                } else {
                    List(results, id: \.self) { hit in
                        Button { onSelect(hit.filePath, hit.line) } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text((hit.filePath as NSString).lastPathComponent)
                                    Text(l10n.t(.symbolLineInfo,
                                                 (hit.filePath as NSString).lastPathComponent,
                                                 hit.filePath, hit.line))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(l10n.t(.referencesTitle, symbolName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel), action: onClose)
                }
            }
        }
    }
}
