import Foundation

// MARK: - 4.0.3 S7 (P2): Native preview service interface (reserved)
//
// This file reserves the interface only — no implementation, no axe /
// swiftui-render integration in 4.0.3. See
// docs/adr/ADR-001-native-preview-service.md for the decision record.
//
// When implemented (post-4.0.3), this service replaces the approximation
// pipeline for views the evaluator cannot resolve: instead of a
// placeholder + diagnostic, CodeBerry will ask a Mac-side service to
// render the real SwiftUI view and return an image + view hierarchy.

/// A render request for one view in one configuration.
struct NativePreviewRequest {
    /// The view's type name (e.g. "HomeView").
    let viewName: String
    /// Full project sources the service needs to compile the view.
    let sources: [String: String]
    /// Target device and appearance.
    let device: String
    let colorScheme: String
}

/// A rendered result from the native service.
struct NativePreviewResult {
    /// Rendered image data (PNG).
    let imageData: Data
    /// Accessibility-tree-derived hierarchy, for inspector parity.
    let hierarchy: String
    /// Diagnostics the native compiler surfaced (warnings/errors).
    let diagnostics: [String]
}

/// Renders real SwiftUI views via a Mac-side service.
///
/// 4.0.3 status: reserved interface. The approximation pipeline
/// (PreviewEvaluator + diagnostics) remains the only engine; this
/// protocol exists so a future implementation can plug in without
/// changing call sites.
protocol NativePreviewService {
    /// Render `request` natively. Throws when the service is unavailable —
    /// callers must fall back to the approximation pipeline.
    func render(_ request: NativePreviewRequest) async throws -> NativePreviewResult

    /// Whether a native service is currently reachable.
    var isAvailable: Bool { get }
}
