import Runestone
import SwiftUI

/// The editor area: open-file tabs (Xcode style), the Runestone code editor,
/// and the Coding Bar above the keyboard.
///
/// M2: Runestone (Tree-sitter highlighting, line numbers, find/replace),
/// Coding Bar with context-aware suggestions, Quick Open, project search,
/// symbol index, local completion, Jump to Definition / Find References,
/// inline diagnostics.
struct EditorPaneView: View {
    @Bindable var store: WorkspaceStore
    /// M5: the Code tab passes false so the editor starts preview-free.
    var previewInitiallyVisible = true

    @State private var controller = EditorController()
    @State private var suggestions: [LocalCompletionEngine.Suggestion] = []
    @State private var showPreview: Bool

    init(store: WorkspaceStore, previewInitiallyVisible: Bool = true) {
        self.store = store
        self.previewInitiallyVisible = previewInitiallyVisible
        self._showPreview = State(initialValue: previewInitiallyVisible)
    }
    /// Editor/preview split, as the preview's share. Persisted; resized by
    /// dragging the canvas's Preview bar.
    @AppStorage("previewSplitFraction") private var previewFraction = 0.45
    @State private var dragBaseFraction: Double?
    @State private var navigateToLine: Int?
    @State private var diagnostics: [CodeDiagnostic] = []
    @State private var diagnosticRanges: [HighlightedRange] = []
    @State private var diagnosticTask: Task<Void, Never>?
    @State private var showingQuickOpen = false
    @State private var quickOpenQuery = ""
    @State private var showingDiagnostics = false
    @State private var showingProjectSearch = false
    @State private var showingReferences = false
    // MARK: - M4: Local history
    @State private var showingHistory = false
    // MARK: - M3: Code -> Preview locate
    @State private var locateLine: Int?
    @State private var locateToken: UUID?
    @State private var referenceSymbolName = ""
    @State private var referenceResults: [ReferenceHit] = []

    var body: some View {
        // Group wraps the conditional so P1-1 modifiers below chain onto a
        // single concrete view value (a bare if/else can't take trailing
        // modifiers in a ViewBuilder).
        Group {
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
                CodingBarView(
                    suggestions: suggestions,
                    onSuggestion: applySuggestion,
                    onKey: { key in
                        switch key {
                        case .left: controller.moveCaret(by: -1)
                        case .right: controller.moveCaret(by: 1)
                        default:
                            if let text = key.insertText { controller.insert(text) }
                        }
                        refreshSuggestions()
                    },
                    onDismissKeyboard: { controller.dismissKeyboard() }
                )
            }
            .sheet(isPresented: $showingQuickOpen) {
                QuickOpenView(
                    query: $quickOpenQuery,
                    files: store.allProjectFiles(),
                    symbolIndex: store.symbolIndex,
                    commands: quickCommands,
                    onSelectFile: { file in
                        showingQuickOpen = false
                        if let wsPath = store.workspacePath(ofProjectRelative: file) {
                            store.openFile(wsPath)
                        }
                    },
                    onSelectSymbol: { sym in
                        showingQuickOpen = false
                        if let wsPath = store.workspacePath(ofProjectRelative: sym.filePath) {
                            store.openFile(wsPath)
                            navigateToLine = sym.line
                        }
                    },
                    onSelectCommand: { cmd in
                        showingQuickOpen = false
                        runCommand(cmd)
                    },
                    onClose: { showingQuickOpen = false }
                )
            }
            .sheet(isPresented: $showingHistory) {
            if let path = store.openFilePath {
                LocalHistoryView(path: path, store: LocalHistoryStore.shared) { entry in
                    store.editorText = entry.content
                    showingHistory = false
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsListView(
                    diagnostics: diagnostics,
                    onSelect: { diag in
                        showingDiagnostics = false
                        navigateToLine = diag.line
                    },
                    onClose: { showingDiagnostics = false }
                )
            }
            .sheet(isPresented: $showingProjectSearch) {
                ProjectSearchView(
                    projectRoot: store.previewProjectRoot(),
                    onSelect: { hit in
                        showingProjectSearch = false
                        if let wsPath = store.workspacePath(ofProjectRelative: hit.filePath) {
                            store.openFile(wsPath)
                            navigateToLine = hit.line
                        }
                    },
                    onClose: { showingProjectSearch = false }
                )
            }
            .sheet(isPresented: $showingReferences) {
                ReferencesListView(
                    symbolName: referenceSymbolName,
                    results: referenceResults,
                    onSelect: { filePath, line in
                        showingReferences = false
                        if let wsPath = store.workspacePath(ofProjectRelative: filePath) {
                            store.openFile(wsPath)
                            navigateToLine = line
                        }
                    },
                    onClose: { showingReferences = false }
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
        // P1-1: consume Preview → Code line jumps requested via the store.
        .onChange(of: store.pendingLineJump) { _, _ in consumeLineJump() }
        .onAppear { consumeLineJump() }
    }

    /// P1-1: applies a pending Preview → Code line jump to the editor.
    private func consumeLineJump() {
        guard let line = store.consumeLineJump() else { return }
        navigateToLine = line
    }

    // MARK: - Editor

    private func editor(_ path: String) -> some View {
        RunestoneEditorView(
            text: $store.editorText,
            fileID: path,
            controller: controller,
            diagnosticRanges: diagnosticRanges,
            navigateToLine: $navigateToLine,
            onCaretWordChange: { _ in refreshSuggestions() },
            onTextChange: {
                refreshSuggestions()
                scheduleDiagnostics()
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { scheduleDiagnostics() }
    }

    // MARK: - Completion

    private func refreshSuggestions() {
        let before = controller.textBeforeCaret
        let word = caretWord(before: before)
        suggestions = LocalCompletionEngine.suggestions(
            prefix: word, textBeforeCaret: before, symbolIndex: store.symbolIndex)
    }

    private func caretWord(before textBeforeCaret: String) -> String {
        var word = ""
        for ch in textBeforeCaret.reversed() {
            if ch.isLetter || ch.isNumber || ch == "_" { word.insert(ch, at: word.startIndex) }
            else { break }
        }
        return word
    }

    private func applySuggestion(_ s: LocalCompletionEngine.Suggestion) {
        if s.caretBacktrack > 0 {
            controller.insert(s.insert)
            controller.moveCaret(by: -s.caretBacktrack)
        } else {
            let word = caretWord(before: controller.textBeforeCaret)
            if !word.isEmpty, s.insert.lowercased().hasPrefix(word.lowercased()) {
                // Replace the typed prefix (identifier completion).
                controller.applyCompletion(s.insert)
            } else {
                controller.insert(s.insert)
            }
        }
        suggestions = []
    }

    // MARK: - Diagnostics

    private func scheduleDiagnostics() {
        diagnosticTask?.cancel()
        let text = store.editorText
        let isSwift = store.openFilePath?.hasSuffix(".swift") ?? false
        diagnosticTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            let diags = await Task.detached {
                isSwift ? InlineDiagnosticsEngine.diagnose(source: text) : []
            }.value
            guard !Task.isCancelled else { return }
            // highlightRanges returns Runestone's non-Sendable HighlightedRange:
            // compute on the main actor instead of crossing isolation.
            await MainActor.run {
                diagnostics = diags
                diagnosticRanges = InlineDiagnosticsEngine.highlightRanges(for: diags, in: text)
            }
        }
    }

    // MARK: - Navigation

    private var caretIdentifier: String? {
        guard let offset = controller.caretOffset else { return nil }
        return CodeNavigation.identifier(at: offset, in: store.editorText)
    }

    private func jumpToDefinition() {
        guard let name = caretIdentifier,
              let path = store.openFilePath,
              let rel = store.projectRelativePath(of: path),
              let sym = store.symbolIndex.definition(of: name, inFile: rel),
              let wsPath = store.workspacePath(ofProjectRelative: sym.filePath) else { return }
        store.openFile(wsPath)
        navigateToLine = sym.line
    }

    /// M3 §三 Preview → Code: jump from an inspected node to its source.
    private func jumpToCode(path: String, line: Int) {
        if path != store.openFilePath { store.openFile(path) }
        navigateToLine = line
    }

    private func findReferences() {
        guard let name = caretIdentifier,
              let path = store.openFilePath,
              let rel = store.projectRelativePath(of: path),
              let sym = store.symbolIndex.definition(of: name, inFile: rel) else { return }
        referenceSymbolName = name
        referenceResults = store.symbolIndex.references(
            of: sym, fileContents: store.swiftFileContents())
        showingReferences = true
    }

    // MARK: - Quick Open commands

    private var quickCommands: [QuickCommand] {
        [
            QuickCommand(id: "project-search", title: L10nService.shared.t(.cmdProjectSearch), icon: "magnifyingglass"),
            QuickCommand(id: "jump-definition", title: L10nService.shared.t(.cmdJumpToDefinition), icon: "arrow.up.right.circle"),
            QuickCommand(id: "find-references", title: L10nService.shared.t(.cmdFindReferences), icon: "list.bullet"),
            QuickCommand(id: "reindex", title: L10nService.shared.t(.cmdRebuildIndex), icon: "arrow.clockwise"),
            QuickCommand(id: "diagnostics", title: L10nService.shared.t(.cmdShowDiagnostics), icon: "exclamationmark.triangle"),
        ]
    }

    private func runCommand(_ cmd: QuickCommand) {
        switch cmd.id {
        case "project-search": showingProjectSearch = true
        case "jump-definition": jumpToDefinition()
        case "find-references": findReferences()
        case "reindex": store.rebuildSymbolIndex()
        case "diagnostics": showingDiagnostics = true
        default: break
        }
    }

    // MARK: - Canvas / tabs

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
                          store: store,
                          locateLine: locateLine,
                          locateToken: locateToken,
                          onJumpToCode: { path, line in jumpToCode(path: path, line: line) })
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            // 4.0.2 P1-10: the active tab is always scrolled into view —
            // new tabs append at the end (off-screen), which used to leave
            // a stale tab visible while the title had already switched.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(store.openTabs, id: \.self) { tab in
                            tabItem(tab)
                                .id(tab)
                        }
                    }
                }
                .onAppear {
                    if let path = store.openFilePath {
                        proxy.scrollTo(path, anchor: .center)
                    }
                }
                .onChange(of: store.openFilePath) { _, newPath in
                    if let newPath {
                        withAnimation(.snappy) {
                            proxy.scrollTo(newPath, anchor: .center)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Divider().frame(height: 20)
            Button {
                showingQuickOpen = true
            } label: {
                Image(systemName: "command")
            }
            .padding(.horizontal, 8)
            Button {
                showingDiagnostics = true
            } label: {
                Image(systemName: diagnostics.contains(where: { !$0.isWarning })
                      ? "exclamationmark.octagon.fill" : "checkmark.circle")
                    .foregroundStyle(diagnostics.contains(where: { !$0.isWarning }) ? .red : .secondary)
            }
            .padding(.horizontal, 8)
            Button {
                jumpToDefinition()
            } label: {
                Image(systemName: "arrow.up.right.circle")
            }
            .padding(.horizontal, 8)
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .padding(.horizontal, 8)
            .disabled(store.openFilePath == nil)
            Button {
                locateLine = controller.caretLine()
                locateToken = UUID()
            } label: {
                Image(systemName: "location.viewfinder")
            }
            .padding(.horizontal, 8)
            .disabled(store.openFilePath?.hasSuffix(".swift") != true)
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
