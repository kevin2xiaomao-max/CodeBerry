import SwiftUI
import UIKit

/// Xcode-Previews-style canvas, 3.0 visual workbench:
/// multi-file index (§二), tap-to-inspect (§三), device presets (§四),
/// canvas-only light/dark (§五), mock data (§七), patch export (§九),
/// before/after (§十), structured diagnostics (§十一).
struct PreviewCanvasView: View {
    let source: String
    /// Which way the editor/preview split runs; the controls bar doubles as
    /// the drag handle for resizing along this axis.
    var dividerAxis: Axis = .vertical
    /// Cumulative drag translation along `dividerAxis`, in points.
    var onDividerDrag: ((CGFloat) -> Void)?
    var onDividerDragEnded: (() -> Void)?
    // MARK: §二 multi-file context (nil = single-file mode)
    var filePath: String?
    var projectRoot: URL?
    var projectName: String?
    var readFile: ((String) -> String?)?
    @Bindable var store: WorkspaceStore

    /// One file rewrite for the inspector apply flow (§三).
    struct FileEdit: Identifiable {
        let id = UUID()
        let path: String          // workspace-relative
        let oldSource: String
        let newSource: String
    }

    @State private var runtime = PreviewRuntime()
    @State private var projectIndex = PreviewProjectIndex()
    @State private var mockStore = PreviewMockStore()
    @State private var inspector = PreviewInspectorState()
    @State private var canvasSettings = PreviewCanvasSettings.shared
    @State private var nodes: [PreviewViewNode] = []
    @State private var diagnostics: [PreviewDiagnostic] = []
    @State private var errorMessage: String?
    @State private var hasRendered = false
    @State private var indexBuilt = false
    /// Keeps the evaluator (captured by button actions) alive across renders.
    @State private var evaluator: PreviewEvaluator?
    @State private var selectMode = false
    @State private var showDiagnostics = false
    @State private var showMockEditor = false
    @State private var errorsOnly = false
    @State private var pendingEdits: [FileEdit]?
    @State private var shareItems: [Any]?
    @State private var showSnapshotDiff = false
    @State private var showWriteFailed = false
    @Bindable private var l10n = L10nService.shared
    @Environment(\.colorScheme) private var systemScheme

    private var hasProjectContext: Bool { projectRoot != nil }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            canvas
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: source) {
            if hasRendered {
                // Debounce live typing; first render is immediate.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }
            updateIndex()
            recompute()
            hasRendered = true
        }
        .onChange(of: runtime.version) {
            recompute()
        }
        .sheet(isPresented: $showDiagnostics) {
            PreviewDiagnosticsSheet(diagnostics: diagnostics, errorsOnly: $errorsOnly)
        }
        .sheet(isPresented: $showMockEditor) {
            PreviewMockSheet(mockStore: mockStore,
                             requirements: mockRequirements(),
                             onDone: { recompute() })
        }
        .sheet(isPresented: Binding(get: { pendingEdits != nil },
                                    set: { if !$0 { pendingEdits = nil } })) {
            if let edits = pendingEdits {
                InspectorDiffSheet(edits: edits,
                                   onConfirm: { applyEdits(edits) },
                                   onCancel: { pendingEdits = nil })
            }
        }
        .sheet(isPresented: $showSnapshotDiff) {
            SnapshotDiffSheet(oldSource: inspector.snapshotSources[filePath ?? ""] ?? "",
                              newSource: source,
                              fileName: (filePath as NSString?)?.lastPathComponent ?? "")
        }
        .alert(l10n.t(.writeFailed), isPresented: $showWriteFailed) {
            Button(l10n.t(.ok), role: .cancel) {}
        }
        .sheet(isPresented: Binding(get: { shareItems != nil },
                                    set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
        .sheet(isPresented: Binding(get: { inspector.selectedID != nil && selectMode && selectedNode() != nil },
                                    set: { if !$0 { inspector.selectedID = nil } })) {
            if let node = selectedNode(), let path = filePath {
                PreviewInspectorSheet(inspector: inspector,
                                      node: node,
                                      source: source,
                                      filePath: path,
                                      index: projectIndex,
                                      readFile: readFile,
                                      onApply: { edits in pendingEdits = edits },
                                      onClose: { inspector.selectedID = nil })
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    if let errorMessage {
                        errorView(errorMessage)
                    } else {
                        deviceSurface(containerWidth: geo.size.width)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
    }

    /// Effective color scheme: canvas-only (§五).
    private var effectiveScheme: ColorScheme {
        canvasSettings.appearance.colorScheme ?? systemScheme
    }

    /// The rendered view tree on a device-sized surface (§四), scaled to fit
    /// the available width.
    private func deviceSurface(containerWidth: CGFloat) -> some View {
        let size = canvasSettings.deviceSize
        let scale = min(1, max(0.2, (containerWidth - 32) / size.width))
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(effectiveScheme == .dark ? Color.black : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
            VStack(spacing: 10) {
                ForEach(nodes.indices, id: \.self) { index in
                    PreviewNodeView(node: nodes[index],
                                    runtime: runtime,
                                    context: renderContext)
                }
            }
            .frame(width: size.width, alignment: .top)
            .clipped()
            .previewColorScheme(canvasSettings.appearance.colorScheme)
            if canvasSettings.showSafeArea {
                safeAreaOverlay(size: size)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .scaleEffect(scale, anchor: .top)
        .frame(width: containerWidth - 32, height: size.height * scale, alignment: .top)
    }

    private func safeAreaOverlay(size: CGSize) -> some View {
        let insets = canvasSettings.safeInsets
        return VStack(spacing: 0) {
            if insets.top > 0 {
                Rectangle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(height: insets.top)
                    .overlay(Divider(), alignment: .bottom)
            }
            Spacer()
            if insets.bottom > 0 {
                Rectangle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(height: insets.bottom)
                    .overlay(Divider(), alignment: .top)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private var renderContext: PreviewRenderContext {
        PreviewRenderContext(inspector: inspector,
                             selectMode: selectMode,
                             onSelect: { inspector.selectedID = $0 })
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Label(l10n.t(.preview), systemImage: "play.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            if projectIndex.isIndexing {
                Label(l10n.t(.indexing), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            diagnosticsButton
            deviceMenu
            appearanceMenu
            inspectorToggle
            mockButton
            moreMenu

            Button {
                runtime.resetAll()   // version bump triggers recompute
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .help(l10n.t(.resetPreviewState))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay {
            if onDividerDrag != nil {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onDividerDrag?(dividerAxis == .vertical ? value.translation.height
                                                            : value.translation.width)
                }
                .onEnded { _ in onDividerDragEnded?() }
        )
    }

    /// §十一 diagnostics button with error count.
    private var diagnosticsButton: some View {
        let errors = diagnostics.filter { $0.severity == .error }
        return Button {
            showDiagnostics = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                if !diagnostics.isEmpty {
                    Text("\(diagnostics.count)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(errors.isEmpty ? Color.secondary : Color.orange)
        }
        .help(l10n.t(.diagnostics))
    }

    /// §四 device picker.
    private var deviceMenu: some View {
        Menu {
            ForEach(PreviewDevicePreset.all) { preset in
                Button {
                    canvasSettings.device = preset
                } label: {
                    Label(l10n.t(preset.nameKey),
                          systemImage: canvasSettings.device == preset ? "checkmark" : "iphone")
                }
            }
            Divider()
            Picker(l10n.t(.orientation), selection: $canvasSettings.orientation) {
                Text(l10n.t(.portrait)).tag(PreviewOrientation.portrait)
                Text(l10n.t(.landscape)).tag(PreviewOrientation.landscape)
            }
            Toggle(l10n.t(.safeArea), isOn: $canvasSettings.showSafeArea)
        } label: {
            Image(systemName: "iphone")
                .font(.caption)
        }
        .help(l10n.t(.device))
    }

    /// §五 canvas-only appearance.
    private var appearanceMenu: some View {
        Menu {
            ForEach(PreviewAppearance.allCases, id: \.self) { appearance in
                Button {
                    canvasSettings.appearance = appearance
                } label: {
                    Label(l10n.t(appearance.key),
                          systemImage: canvasSettings.appearance == appearance ? "checkmark"
                            : appearance == .light ? "sun.max" : appearance == .dark ? "moon" : "circle.lefthalf.filled")
                }
            }
        } label: {
            Image(systemName: canvasSettings.appearance == .dark ? "moon.fill"
                    : canvasSettings.appearance == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                .font(.caption)
        }
        .help(l10n.t(.appearance))
    }

    /// §三 inspector tap-to-select mode.
    private var inspectorToggle: some View {
        Button {
            selectMode.toggle()
            if !selectMode { inspector.selectedID = nil }
        } label: {
            Image(systemName: selectMode ? "cursorarrow.click.2" : "cursorarrow.click")
                .font(.caption)
                .foregroundStyle(selectMode ? Color.accentColor : .secondary)
        }
        .help(l10n.t(.inspector))
    }

    /// §七 mock data.
    private var mockButton: some View {
        Button {
            showMockEditor = true
        } label: {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.caption)
                .foregroundStyle(mockStore.isEmpty ? .secondary : Color.accentColor)
        }
        .help(l10n.t(.mockData))
    }

    private var moreMenu: some View {
        Menu {
            Button(l10n.t(.saveSnapshot), systemImage: "camera") {
                if let path = filePath { inspector.snapshotSources[path] = source }
            }
            Button(l10n.t(.before) + " / " + l10n.t(.after), systemImage: "square.split.1x2") {
                showSnapshotDiff = true
            }
            .disabled(inspector.snapshotSources[filePath ?? ""] == nil)
            Divider()
            Button(l10n.t(.generateFixture), systemImage: "doc.badge.plus") {
                generateFixture()
            }
            Button(l10n.t(.exportPatch), systemImage: "square.and.arrow.up") {
                exportPatch()
            }
            .disabled(inspector.snapshotSources[filePath ?? ""] == nil)
            Button(l10n.t(.copyCode), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = source
            }
            Divider()
            Button(l10n.t(.reset), systemImage: "arrow.counterclockwise") {
                inspector.resetAll()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.caption)
        }
        .help(l10n.t(.more))
    }

    // MARK: - Interpretation

    private func updateIndex() {
        guard hasProjectContext,
              let root = projectRoot, let name = projectName, let readFile else { return }
        if !indexBuilt { projectIndex.isIndexing = true }
        projectIndex.update(projectRoot: root,
                            projectName: name,
                            currentPath: filePath,
                            currentSource: source,
                            readFile: readFile)
        projectIndex.isIndexing = false
        indexBuilt = true
    }

    private func recompute() {
        do {
            let engine = PreviewEngine(source: source)
            guard let (file, converter) = engine.parseTree() else {
                throw PreviewError(.errPreviewPaused)
            }
            var doc = PreviewDocument()
            PreviewEngine.collect(into: &doc, from: file)
            guard doc.previewBody != nil || !doc.viewOrder.isEmpty else {
                throw PreviewError(.errNoPreviewableView)
            }
            let evaluator = PreviewEvaluator(doc: doc, runtime: runtime)
            evaluator.fileName = (filePath as NSString?)?.lastPathComponent ?? ""
            evaluator.converter = converter
            evaluator.projectIndex = hasProjectContext ? projectIndex : nil
            evaluator.mockStore = mockStore
            nodes = try evaluator.renderRoot()
            diagnostics = evaluator.diagnostics
            errorMessage = nil
            self.evaluator = evaluator
        } catch {
            errorMessage = (error as? PreviewError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Inspector support

    /// Find the selected node anywhere in the tree.
    private func selectedNode() -> PreviewViewNode? {
        guard let id = inspector.selectedID else { return nil }
        for node in nodes {
            if let found = findNode(id: id, in: node) { return found }
        }
        return nil
    }

    private func findNode(id: String, in node: PreviewViewNode) -> PreviewViewNode? {
        if node.source?.nodeID == id { return node }
        let children: [PreviewViewNode]
        switch node.kind {
        case .stack(_, _, _, let c): children = c
        case .button(let label, _): children = label
        case .list(let c): children = c
        case .group(let c): children = c
        default: children = []
        }
        for child in children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }

    /// §三 apply confirmed edits (§十三: failed writes keep the original file).
    private func applyEdits(_ edits: [FileEdit]) {
        pendingEdits = nil
        var ok = true
        for edit in edits {
            // §十三: never overwrite on syntax errors — re-parse the new source first.
            guard PreviewEngine(source: edit.newSource).parseTree() != nil else {
                ok = false
                continue
            }
            if !store.writePreviewFile(edit.path, content: edit.newSource) { ok = false }
        }
        if !ok { showWriteFailed = true }
        inspector.selectedID = nil
        updateIndex()
        recompute()
    }

    /// Mock requirements of the rendered root view (§七).
    private func mockRequirements() -> [PreviewMockRequirement] {
        guard let evaluator else { return [] }
        var out: [PreviewMockRequirement] = []
        for name in evaluator.doc.viewOrder {
            if let view = evaluator.activeViews[name] {
                out += view.mockRequirements
            }
        }
        return out
    }

    // MARK: - §八 fixture generation / §九 patch export

    /// §八: one-tap fixture of the current canvas — shares the current source
    /// as a `<Name>Fixture.swift` file.
    private func generateFixture() {
        let name = ((filePath as NSString?)?.deletingPathExtension as NSString?)?.lastPathComponent
            ?? "Preview"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)Fixture.swift")
        guard (try? source.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        shareItems = [url]
    }

    /// §九: export the snapshot→current diff as a `.patch` file. Export only —
    /// nothing is pushed automatically.
    private func exportPatch() {
        guard let path = filePath,
              let old = inspector.snapshotSources[path] else { return }
        let fileName = (path as NSString).lastPathComponent
        let diff = PreviewPatch.unifiedDiff(oldText: old, newText: source, fileName: fileName)
        guard !diff.isEmpty,
              let url = PreviewPatch.patchFileURL(diff: diff, fileName: fileName) else { return }
        shareItems = [url]
    }
}

// MARK: - Small helpers

private extension View {
    /// Canvas-only color scheme (§五): nil inherits the system scheme.
    @ViewBuilder
    func previewColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
