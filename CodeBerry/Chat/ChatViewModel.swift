import SwiftUI
import AgentKit

struct ChatMessage: Identifiable {
    enum Kind { case user, assistant, tool }
    let id = UUID()
    let kind: Kind
    var text: String
    var detail: String? = nil   // tool input/output detail
}

extension ModelProvider {
    var shortName: String {
        switch self {
        case .onDevice: "On-Device"
        case .claude: "Claude"
        case .openAI: "GPT"
        }
    }

    var subtitle: String {
        switch self {
        case .onDevice: "Apple Intelligence — private & free"
        case .claude: "Anthropic API"
        case .openAI: "OpenAI API"
        }
    }

    var symbolName: String {
        switch self {
        case .onDevice: "apple.logo"
        case .claude: "sparkles"
        case .openAI: "bolt.fill"
        }
    }
}

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var input = ""
    var isWorking = false
    var errorText: String?

    /// Default stays on the free, private on-device model.
    var provider: ModelProvider = .onDevice { didSet { resetSession() } }

    var claudeAPIKey: String = KeychainStore.load(key: "anthropic-api-key") ?? "" {
        didSet { KeychainStore.save(key: "anthropic-api-key", value: claudeAPIKey); resetSession() }
    }
    var openAIAPIKey: String = KeychainStore.load(key: "openai-api-key") ?? "" {
        didSet { KeychainStore.save(key: "openai-api-key", value: openAIAPIKey); resetSession() }
    }

    let workspaceURL: URL

    /// Folder name of the open project. The agent's file tools are rooted
    /// here so relative paths match what the navigator shows inside the
    /// project; nil (Projects home screen) roots them at the workspace
    /// itself, which the new-project flow relies on.
    var currentProjectFolder: String? {
        didSet { if currentProjectFolder != oldValue { resetSession() } }
    }

    /// Fired after each tool result and at turn end so the editor can pick up
    /// files the agent created or changed.
    var onWorkspaceMutated: (() -> Void)?
    /// Fired before a message goes out so unsaved editor changes hit disk first.
    var onBeforeSend: (() -> Void)?

    private var session: (any AgentModelSession)?

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    private func makeSessionIfNeeded() throws -> any AgentModelSession {
        if let session { return session }
        let root = currentProjectFolder.map {
            workspaceURL.appendingPathComponent($0, isDirectory: true)
        } ?? workspaceURL
        let agent = Agent(workspace: Workspace(root: root))
        let s = try agent.makeSession(provider: provider,
                                      claudeAPIKey: claudeAPIKey.isEmpty ? nil : claudeAPIKey,
                                      openAIAPIKey: openAIAPIKey.isEmpty ? nil : openAIAPIKey)
        session = s
        return s
    }

    func resetSession() {
        session = nil
        messages = []
        errorText = nil
    }

    func sendCurrentInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        send(text)
    }

    func createNewProject(named name: String) {
        send("Create a new iOS Xcode project named \"\(name)\" using the create_xcode_project tool, then tell me what was created.")
    }

    func send(_ text: String) {
        guard !isWorking else { return }
        onBeforeSend?()
        messages.append(ChatMessage(kind: .user, text: text))
        isWorking = true
        errorText = nil

        Task {
            do {
                let session = try makeSessionIfNeeded()
                var assistantIndex: Int? = nil
                for try await event in session.send(text) {
                    switch event {
                    case .textDelta(let delta):
                        if let i = assistantIndex {
                            messages[i].text += delta
                        } else {
                            messages.append(ChatMessage(kind: .assistant, text: delta))
                            assistantIndex = messages.count - 1
                        }
                    case .toolCall(let name, let inputJSON):
                        assistantIndex = nil   // next text starts a new bubble
                        messages.append(ChatMessage(kind: .tool, text: "🔧 \(name)", detail: inputJSON))
                    case .toolResult(let name, let output):
                        messages.append(ChatMessage(kind: .tool, text: "✓ \(name)",
                                                    detail: String(output.prefix(800))))
                        onWorkspaceMutated?()
                    case .finished:
                        break
                    }
                }
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
            onWorkspaceMutated?()
        }
    }
}
