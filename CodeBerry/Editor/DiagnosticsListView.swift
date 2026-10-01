import SwiftUI

/// Lists the current file's diagnostics, grouped by tier (§14).
/// Tap a diagnostic to jump to its line.
struct DiagnosticsListView: View {
    let diagnostics: [CodeDiagnostic]
    let onSelect: (CodeDiagnostic) -> Void
    let onClose: () -> Void
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        NavigationStack {
            Group {
                if diagnostics.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.t(.diagnosticsNone), systemImage: "checkmark.circle")
                    } description: {
                        Text(l10n.t(.diagnosticsEmpty))
                    }
                } else {
                    List {
                        ForEach(DiagnosticTier.allCases, id: \.rawValue) { tier in
                            let items = diagnostics.filter { $0.tier == tier }
                            if !items.isEmpty {
                                Section(tier.chineseLabel) {
                                    ForEach(items) { diag in
                                        Button { onSelect(diag) } label: {
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: diag.isWarning
                                                      ? "exclamationmark.triangle.fill"
                                                      : "xmark.octagon.fill")
                                                    .foregroundStyle(diag.isWarning ? .orange : .red)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(diag.message)
                                                        .font(.callout)
                                                    Text(l10n.t(.diagnosticPosition, diag.line, diag.column))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(l10n.t(.diagnosticsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel), action: onClose)
                }
            }
        }
    }
}

