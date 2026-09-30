import SwiftUI

/// Lite settings: workspace info only. No AI providers, no companion Mac —
/// those belong to the full AgentKit build.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    LabeledContent("Location", value: "On My iPhone › CodeBerry")
                    Text("Your workspace is the app's Documents folder — files are also visible in the Files app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("CodeBerry Lite — Swift editor + SwiftUI preview canvas, no AI agent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
