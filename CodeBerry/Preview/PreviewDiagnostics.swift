import Foundation
import SwiftSyntax

// MARK: - §十一 Diagnostics

/// Severity levels for preview diagnostics (§十一):
/// - Error: syntax errors, genuinely unresolvable identifiers, evaluator
///   fatals — the preview may be wrong.
/// - Warning: unavailable-but-approximated APIs (SwiftData, external
///   packages) — rendered best-effort or skipped.
/// - Info: informational notes that don't affect the preview (e.g. a type
///   fell back to preview defaults).
/// - NeedsMock: the preview needs Mock/Fixture data to render fully.
/// - Ignored: cosmetic modifiers the engine deliberately skips.
enum PreviewDiagnosticSeverity: String, CaseIterable {
    case error
    case warning
    case info
    case needsMock
    case ignored

    var key: L10nKey {
        switch self {
        case .error: return .severityError
        case .warning: return .severityWarning
        case .info: return .severityInfo
        case .needsMock: return .severityNeedsMock
        case .ignored: return .severityIgnored
        }
    }

    /// SF Symbol for the diagnostics UI.
    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .needsMock: return "tray.and.arrow.down.fill"
        case .ignored: return "eye.slash.fill"
        }
    }

    /// 4.0.2 P1-9: errors block the preview; everything else is advisory.
    var blocksPreview: Bool { self == .error }
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
