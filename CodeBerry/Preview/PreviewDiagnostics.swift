import Foundation
import SwiftSyntax

// MARK: - §十一 Diagnostics

/// Severity levels for preview diagnostics (§十一):
/// - Error: syntax errors, unknown identifiers — the preview may be wrong.
/// - Warning: unsupported APIs — rendered as best-effort or skipped.
/// - Ignored: cosmetic modifiers the engine deliberately skips.
enum PreviewDiagnosticSeverity: String, CaseIterable {
    case error
    case warning
    case ignored

    var key: L10nKey {
        switch self {
        case .error: return .severityError
        case .warning: return .severityWarning
        case .ignored: return .severityIgnored
        }
    }

    /// SF Symbol for the diagnostics UI.
    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .ignored: return "eye.slash.fill"
        }
    }
}

/// One structured diagnostic: Chinese message (§一) + file + line + API (§十一).
struct PreviewDiagnostic: Identifiable, Hashable {
    let id = UUID()
    let severity: PreviewDiagnosticSeverity
    let key: L10nKey
    let params: [String]
    let file: String
    let line: Int?
    /// The SwiftUI API / modifier / call this diagnostic is about (may be nil).
    let api: String?

    var message: String {
        let template = L10nService.shared.t(key)
        guard !params.isEmpty else { return template }
        return String(format: template, locale: Locale.current, arguments: params)
    }

    /// "文件名 · 第 N 行" subtitle, or just the file name when no line is known.
    var locationText: String {
        if let line {
            return L10nService.shared.t(.fileLine, file, line)
        }
        return file
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PreviewDiagnostic, rhs: PreviewDiagnostic) -> Bool {
        lhs.id == rhs.id
    }
}
