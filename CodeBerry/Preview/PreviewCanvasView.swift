import SwiftUI

/// Xcode-Previews-style canvas: interprets the current file's SwiftUI code
/// and renders it live, with light/dark toggle, state restart, and
/// diagnostics for unsupported syntax.
struct PreviewCanvasView: View {
    let source: String
    /// Which way the editor/preview split runs; the controls bar doubles as
    /// the drag handle for resizing along this axis.
    var dividerAxis: Axis = .vertical
    /// Cumulative drag translation along `dividerAxis`, in points.
    var onDividerDrag: ((CGFloat) -> Void)?
    var onDividerDragEnded: (() -> Void)?

    @State private var runtime = PreviewRuntime()
    @State private var nodes: [PreviewViewNode] = []
    @State private var warnings: [String] = []
    @State private var errorMessage: String?
    @State private var previewScheme: ColorScheme = .light
    @State private var hasRendered = false
    /// Keeps the evaluator (captured by button actions) alive across renders.
    @State private var evaluator: PreviewEvaluator?

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
            recompute()
            hasRendered = true
        }
        .onChange(of: runtime.version) {
            recompute()
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let errorMessage {
                    errorView(errorMessage)
                } else {
                    deviceSurface
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    /// The rendered view tree on a device-like surface.
    private var deviceSurface: some View {
        VStack(spacing: 10) {
            ForEach(nodes.indices, id: \.self) { index in
                PreviewNodeView(node: nodes[index], runtime: runtime)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(20)
        .background(previewScheme == .dark ? Color.black : Color.white)
        .environment(\.colorScheme, previewScheme)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .frame(maxWidth: 420)
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
        HStack(spacing: 14) {
            Label("Preview", systemImage: "play.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Spacer()

            if !warnings.isEmpty {
                Menu {
                    ForEach(warnings, id: \.self) { warning in
                        Text(warning)
                    }
                } label: {
                    Label("\(warnings.count)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Button {
                previewScheme = previewScheme == .dark ? .light : .dark
            } label: {
                Image(systemName: previewScheme == .dark ? "moon.fill" : "sun.max")
                    .font(.caption)
            }

            Button {
                runtime.resetAll()   // version bump triggers recompute
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
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

    // MARK: Interpretation

    private func recompute() {
        do {
            let doc = try PreviewEngine(source: source).parse()
            let evaluator = PreviewEvaluator(doc: doc, runtime: runtime)
            nodes = try evaluator.renderRoot()
            warnings = evaluator.warnings
            errorMessage = nil
            self.evaluator = evaluator
        } catch {
            errorMessage = (error as? PreviewError)?.message ?? error.localizedDescription
        }
    }
}
