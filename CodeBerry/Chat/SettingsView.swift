import SwiftUI

struct SettingsView: View {
    @Bindable var model: ChatViewModel
    var companion: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showManualConnect = false
    @State private var manualAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                companionSection
                Section("On-Device (Apple Intelligence)") {
                    Text("Runs Apple's on-device model — private and free, no key needed. Best for planning, explanations, and small edits; switch to Claude or GPT for heavy code generation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Claude (Anthropic API)") {
                    SecureField("API key (sk-ant-…)", text: $model.claudeAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Stored in the iOS Keychain. Get a key at platform.claude.com — API usage is billed per token (separate from a Claude.ai subscription).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("GPT (OpenAI API)") {
                    SecureField("API key (sk-…)", text: $model.openAIAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Stored in the iOS Keychain. Get a key at platform.openai.com — API usage is billed per token (separate from a ChatGPT subscription).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Workspace") {
                    LabeledContent("Location", value: "On My iPhone › CodeBerry")
                    Text("Your workspace is the app's Documents folder — files are also visible in the Files app.")
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
        .onAppear { companion.startBrowsing() }
        .onDisappear { if !companion.isConnected { companion.stopBrowsing() } }
    }

    // MARK: Companion Mac

    @ViewBuilder
    private var companionSection: some View {
        Section("Companion Mac — Build & Run (Preview)") {
            switch companion.state {
            case .connected(let welcome):
                LabeledContent("Connected to", value: welcome.serverName)
                LabeledContent("AgentOS", value: "v\(welcome.appVersion)")
                if let latency = companion.latencyText {
                    LabeledContent("Latency", value: latency)
                }
                LabeledContent("Capabilities", value: welcome.capabilities.joined(separator: ", "))
                Button("Disconnect", role: .destructive) {
                    companion.disconnect()
                }
            case .connecting(let name):
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Connecting to \(name)…")
                        .foregroundStyle(.secondary)
                }
            case .disconnected:
                if companion.macs.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for Macs running AgentOS…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(companion.macs) { mac in
                        Button {
                            companion.connect(to: mac)
                        } label: {
                            Label(mac.name, systemImage: "desktopcomputer")
                        }
                    }
                }
                Button {
                    manualAddress = companion.lastManualAddress
                    showManualConnect = true
                } label: {
                    Label("Connect by Address…", systemImage: "network")
                }
                if let error = companion.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Text("Nearby Macs running AgentOS appear automatically — even without shared WiFi (peer-to-peer). From a different network, use Connect by Address with the host:port shown in the Mac's AgentOS settings (requires Tailscale/VPN or port forwarding).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("Connect by Address", isPresented: $showManualConnect) {
            TextField("host:port, e.g. my-mac.local:57452", text: $manualAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Connect") { companion.connectManually(manualAddress) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The address is shown in AgentOS Settings on your Mac.")
        }
    }
}
