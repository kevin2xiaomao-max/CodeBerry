import Foundation
import SwiftUI

// MARK: - M3 §19 Before / After
//
// Save a snapshot before a change; after the change show Before/After.
// iPhone: toggle. iPad: side-by-side (via horizontal size class).
// No permanent screenshot history is kept — one snapshot slot (§19).

/// One snapshot slot: the rendered image + the source that produced it.
/// Main-actor confined (UIImage is not Sendable); no Sendable conformance.
struct BeforeAfterSnapshot {
    let image: UIImage
    let source: String
    let date: Date
}

/// Not @MainActor: the canvas drives it from nonisolated view closures;
/// all access happens on the main thread via SwiftUI in practice.
@Observable
final class BeforeAfterStore {
    var before: BeforeAfterSnapshot?
    var showingBefore = false

    var hasSnapshot: Bool { before != nil }

    func capture(image: UIImage, source: String) {
        before = BeforeAfterSnapshot(image: image, source: source, date: Date())
        showingBefore = false
    }

    func clear() {
        before = nil
        showingBefore = false
    }
}

/// Captures the canvas via ImageRenderer (2x) — call from the canvas view.
/// @MainActor because ImageRenderer is @MainActor; canvas UI actions always
/// run on the main thread.
@MainActor
func renderSnapshot<Content: View>(of content: Content, scale: CGFloat = 2) -> UIImage? {
    let renderer = ImageRenderer(content: content)
    renderer.scale = scale
    return renderer.uiImage
}

/// Before/After viewer: toggle on iPhone, side-by-side on iPad (§19).
struct BeforeAfterView<After: View>: View {
    let snapshot: BeforeAfterSnapshot
    @Binding var showingBefore: Bool
    let after: () -> After
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        Group {
            if hSizeClass == .regular {
                HStack(spacing: 0) {
                    beforePane
                    Divider()
                    afterPane
                }
            } else {
                VStack(spacing: 0) {
                    Picker("", selection: $showingBefore) {
                        Text(l10n.t(.beforeLabel)).tag(true)
                        Text(l10n.t(.afterLabel)).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                    if showingBefore { beforePane } else { afterPane }
                }
            }
        }
    }

    private var beforePane: some View {
        VStack(spacing: 4) {
            Text(l10n.t(.beforeLabel))
                .font(.caption).foregroundStyle(.secondary)
            Image(uiImage: snapshot.image)
                .resizable().scaledToFit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var afterPane: some View {
        VStack(spacing: 4) {
            Text(l10n.t(.afterLabel))
                .font(.caption).foregroundStyle(.secondary)
            after()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
