import SwiftUI

/// The editor area: open-file tabs (Xcode style), the code editor, and a
/// keyboard bar that flips between symbol keys and autocomplete suggestions.
struct EditorPaneView: View {
    @Bindable var store: WorkspaceStore

    @State private var controller = EditorController()
    @State private var suggestions: [String] = []
    @State private var showPreview = true
    /// Editor/preview split, as the preview's share. Persisted; resized by
    /// dragging the canvas's Preview bar.
    @AppStorage("previewSplitFraction") private var previewFraction = 0.45
    @State private var dragBaseFraction: Double?
    private let autocomplete = AutocompleteEngine()

    var body: some View {
        if let path = store.openFilePath {
            VStack(spacing: 0) {
                tabBar
                Divider()
                GeometryReader { geometry in
                    if showPreview && path.hasSuffix(".swift") {
                        // Xcode-style canvas: beside the editor when wide,
                        // below it when compact.
                        if geometry.size.width >= 700 {
                            HStack(spacing: 0) {
                                editor(path)
                                Divider()
                                canvas(axis: .horizontal, total: geometry.size.width, path: path)
                                    .frame(width: geometry.size.width * previewFraction)
                            }
                        } else {
                            VStack(spacing: 0) {
                                editor(path)
                                Divider()
                                canvas(axis: .vertical, total: geometry.size.height, path: path)
                                    .frame(height: geometry.size.height * previewFraction)
                            }
                        }
                    } else {
                        editor(path)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorAccessoryBar(
                    suggestions: suggestions,
                    onSuggestion: { word in
                        controller.applyCompletion(word)
                        suggestions = []
                    },
                    onSymbol: { symbol in
                        controller.insert(symbol == "⇥" ? "    " : symbol)
                    },
                    onDismissKeyboard: { controller.dismissKeyboard() }
                )
            }
        } else {
            ContentUnavailableView {
                Label(L10nService.shared.t(.noFileOpen), systemImage: "swift")
            } description: {
                Text(L10nService.shared.t(.noFileOpenDesc))
            }
        }
    }

    private func canvas(axis: Axis, total: CGFloat, path: String) -> some View {
        PreviewCanvasView(source: store.editorText,
                          dividerAxis: axis,
                          onDividerDrag: { translation in
                              let base = dragBaseFraction ?? previewFraction
                              if dragBaseFraction == nil { dragBaseFraction = base }
                              // Dragging toward the editor grows the preview.
                              let proposed = base - Double(translation) / Double(total)
                              previewFraction = min(0.8, max(0.2, proposed))
                          },
                          onDividerDragEnded: { dragBaseFraction = nil },
                          filePath: path,
                          projectRoot: store.previewProjectRoot(),
                          projectName: store.currentProject,
                          readFile: { store.previewFileContent($0) },
                          store: store)
    }

    private func editor(_ path: String) -> some View {
        CodeEditorView(text: $store.editorText,
                       fileID: path,
                       controller: controller) { prefix in
            suggestions = autocomplete.suggestions(prefix: prefix, in: store.editorText)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.openTabs, id: \.self) { tab in
                        tabItem(tab)
                    }
                }
            }
            Spacer(minLength: 8)
            Divider().frame(height: 20)
            Button {
                withAnimation(.snappy) { showPreview.toggle() }
            } label: {
                Image(systemName: showPreview ? "eye.fill" : "eye")
                    .font(.subheadline)
            }
            .disabled(!(store.openFilePath?.hasSuffix(".swift") ?? false))
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(.bar)
    }

    private func tabItem(_ tab: String) -> some View {
        let isActive = tab == store.openFilePath
        return HStack(spacing: 6) {
            Image(systemName: "swift")
                .font(.caption2)
                .foregroundStyle(isActive ? .orange : .secondary)
            Text((tab as NSString).lastPathComponent)
                .font(.callout)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
            if isActive && store.isDirty {
                Circle().fill(.secondary).frame(width: 5, height: 5)
            }
            Button {
                store.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(isActive ? Color.primary.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.openFile(tab) }
    }
}

/// Sits above the keyboard: completion suggestions while typing an
/// identifier, code symbol keys otherwise.
struct EditorAccessoryBar: View {
    let suggestions: [String]
    let onSuggestion: (String) -> Void
    let onSymbol: (String) -> Void
    let onDismissKeyboard: () -> Void

    private static let symbols = ["⇥", "{", "}", "(", ")", "[", "]", "\"", ".",
                                  ":", ";", ",", "=", "+", "-", "*", "/", "<",
                                  ">", "!", "?", "&", "|", "_", "->"]

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if suggestions.isEmpty {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button {
                                onSymbol(symbol)
                            } label: {
                                Text(symbol)
                                    .font(.system(size: 15, design: .monospaced))
                                    .frame(minWidth: 24)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .controlSize(.small)
                        }
                    } else {
                        ForEach(suggestions, id: \.self) { word in
                            Button {
                                onSuggestion(word)
                            } label: {
                                Text(word)
                                    .font(.system(size: 14, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .controlSize(.small)
                            .tint(.accentColor)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Divider().frame(height: 22)
            Button {
                onDismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 42)
        .background(.bar)
    }
}
