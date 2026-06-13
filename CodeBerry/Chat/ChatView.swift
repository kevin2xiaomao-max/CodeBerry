import SwiftUI
import AgentKit

/// Agent chat panel. No header — everything lives in the Liquid Glass
/// composer: "+" menu (new chat), model selector, and send button, with
/// messages scrolling underneath it.
struct ChatView: View {
    @Bindable var model: ChatViewModel

    private static let samplePrompts = [
        "Create a SwiftUI pomodoro timer view",
        "List my files and explain this project",
        "Start a new iOS app project called MyApp"
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if model.messages.isEmpty && !model.isWorking {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        MessageRow(message: message)
                    }
                    if model.isWorking {
                        TypingIndicator()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let error = model.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
                composer
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 4)
        }
    }

    // MARK: Liquid Glass composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Ask the agent to build something…", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .onSubmit { model.sendCurrentInput() }

            HStack(spacing: 16) {
                Menu {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        model.resetSession()
                    }
                    .disabled(model.isWorking)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .tint(.primary)

                modelMenu

                Spacer()

                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $model.provider) {
                ForEach(ModelProvider.allCases) { provider in
                    Label {
                        Text(provider.shortName)
                        Text(provider.subtitle)
                    } icon: {
                        Image(systemName: provider.symbolName)
                    }
                    .tag(provider)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.provider.symbolName)
                    .font(.caption)
                Text(model.provider.shortName)
                    .font(.subheadline.weight(.medium))
            }
            .contentShape(Rectangle())
        }
        .tint(.secondary)
    }

    private var sendButton: some View {
        Button {
            model.sendCurrentInput()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !model.isWorking && !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("CodeBerry Agent")
                .font(.headline)
            Text("Ask it to create files, build features, or explain code in your workspace.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(Self.samplePrompts, id: \.self) { prompt in
                    Button {
                        model.send(prompt)
                    } label: {
                        Text(prompt)
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().strokeBorder(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Message bubbles

private struct MessageRow: View {
    let message: ChatMessage
    @State private var expanded = false

    private static let userBubble = LinearGradient(
        colors: [Color(red: 0.25, green: 0.57, blue: 1.0), Color(red: 0.0, green: 0.48, blue: 1.0)],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Self.userBubble,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.vertical, 2)
            .id(message.id)
        case .assistant:
            HStack {
                Text(LocalizedStringKey(message.text))   // renders markdown
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 60)
            }
            .padding(.vertical, 2)
            .id(message.id)
        case .tool:
            DisclosureGroup(isExpanded: $expanded) {
                if let detail = message.detail {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } label: {
                Text(message.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().strokeBorder(.quaternary, lineWidth: 1)
                .opacity(expanded ? 0 : 1))
            .id(message.id)
        }
    }
}

/// Three pulsing dots, iMessage style.
private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(animating ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever()
                        .delay(Double(i) * 0.15), value: animating)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { animating = true }
    }
}
