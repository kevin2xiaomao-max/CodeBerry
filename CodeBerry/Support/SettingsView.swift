import SwiftUI

/// Lite settings: language, workspace info, appearance, about.
/// No AI chat configuration, no agent settings — this app is Lite by design.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var l10n = L10nService.shared
    @Bindable private var canvasSettings = PreviewCanvasSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(l10n.t(.language), selection: $l10n.language) {
                        Text(l10n.t(.languageFollowSystem)).tag(AppLanguage.system)
                        Text(l10n.t(.languageZhHans)).tag(AppLanguage.zhHans)
                        Text(l10n.t(.languageEnglish)).tag(AppLanguage.english)
                    }
                }

                Section(l10n.t(.settingsWorkspace)) {
                    LabeledContent(l10n.t(.settingsLocation)) {
                        Text(workspacePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(l10n.t(.settingsLocationDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(l10n.t(.appearance)) {
                    Picker(l10n.t(.appearance), selection: $canvasSettings.appearance) {
                        Text(l10n.t(.followSystem)).tag(PreviewAppearance.followSystem)
                        Text(l10n.t(.light)).tag(PreviewAppearance.light)
                        Text(l10n.t(.dark)).tag(PreviewAppearance.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section(l10n.t(.settingsAbout)) {
                    LabeledContent(l10n.t(.settingsVersion)) {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Text(l10n.t(.settingsAboutDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(l10n.t(.settings))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.done)) { dismiss() }
                }
            }
        }
    }

    private var workspacePath: String {
        do {
            return try LiteWorkspace.resolve("").path
        } catch {
            return "—"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
