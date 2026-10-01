import Foundation
import Runestone
import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import UIKit

/// The three diagnostic tiers (§14). Chinese labels are the user-facing
/// distinction the spec requires.
enum DiagnosticTier: String, CaseIterable {
    /// Parse-level problems from SwiftParser.
    case syntax
    /// CodeBerry Preview understands the syntax but not the semantics yet (M3).
    case previewSemantic
    /// Runs only with device capabilities CodeBerry can't provide (M3).
    case unsupportedRuntime

    var chineseLabel: String {
        switch self {
        case .syntax: return "语法错误"
        case .previewSemantic: return "CodeBerry Preview 尚未实现此语义"
        case .unsupportedRuntime: return "需要 Mock"
        }
    }

    var color: UIColor {
        switch self {
        case .syntax: return .systemRed
        case .previewSemantic: return .systemOrange
        case .unsupportedRuntime: return .systemYellow
        }
    }
}

/// One inline diagnostic in the open file.
struct CodeDiagnostic: Identifiable {
    let id = UUID()
    let tier: DiagnosticTier
    /// 1-based.
    let line: Int
    let column: Int
    /// Chinese user-facing message.
    let message: String
    /// Raw English message from the parser (for debugging).
    let rawMessage: String
    let isWarning: Bool
}

/// Produces tiered, Chinese-labeled diagnostics for the open file.
///
/// M2 implements the **syntax** tier via SwiftParser + ParseDiagnosticsGenerator
/// (SwiftSyntax bridge). The previewSemantic / unsupportedRuntime tiers are
/// populated by M3's ProjectAnalyzer; the model and UI already distinguish them.
enum InlineDiagnosticsEngine {
    /// Parses `source` and returns syntax-tier diagnostics, sorted by position.
    /// Pure function — unit-tested (`DiagnosticsTests`, `SwiftSyntaxBridgeTests`).
    static func diagnose(source: String, fileName: String = "file.swift") -> [CodeDiagnostic] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        let diags = ParseDiagnosticsGenerator.diagnostics(for: tree)
        let filtered = diags.filter { $0.diagMessage.severity == .error || $0.diagMessage.severity == .warning }
        let mapped: [CodeDiagnostic] = filtered.map { toCodeDiagnostic($0, converter: converter) }
        return mapped.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }

    private static func toCodeDiagnostic(
        _ diag: Diagnostic,
        converter: SourceLocationConverter) -> CodeDiagnostic {
        let loc = converter.location(for: diag.position)
        return CodeDiagnostic(
            tier: .syntax,
            line: loc.line,
            column: loc.column,
            message: chineseMessage(for: diag),
            rawMessage: diag.diagMessage.message,
            isWarning: diag.diagMessage.severity == .warning)
    }

    /// Runestone highlight ranges for diagnostic underlines.
    static func highlightRanges(for diagnostics: [CodeDiagnostic],
                                in source: String) -> [HighlightedRange] {
        let ns = source as NSString
        return diagnostics.compactMap { diag -> HighlightedRange? in
            // Underline the whole line for visibility on small screens.
            guard let range = lineRange(line: diag.line, in: ns) else { return nil }
            return HighlightedRange(
                range: range,
                color: diag.tier.color.withAlphaComponent(diag.isWarning ? 0.25 : 0.35),
                cornerRadius: 3)
        }
    }

    // MARK: - Chinese messages

    /// Maps common parser diagnostics to Chinese; falls back to the raw
    /// English message prefixed with the tier label.
    static func chineseMessage(for diag: Diagnostic) -> String {
        // String(reflecting:) renders "MessageID(domain: ..., id: ...)"
        // regardless of member names — robust across swift-syntax versions.
        let idString = String(reflecting: diag.diagMessage.diagnosticID)
        for (fragment, chinese) in Self.idTranslations {
            if idString.contains(fragment) { return chinese }
        }
        // Heuristic fallbacks on the English text.
        let raw = diag.diagMessage.message
        for (fragment, chinese) in Self.fragmentTranslations {
            if raw.contains(fragment) { return chinese }
        }
        return "语法错误：\(raw)"
    }

    // MARK: - Private

    private static func lineRange(line: Int, in ns: NSString) -> NSRange? {
        var offset = 0
        var current = 1
        while current < line && offset < ns.length {
            let r = ns.lineRange(for: NSRange(location: offset, length: 0))
            let next = NSMaxRange(r)
            if next <= offset { return nil }
            offset = next
            current += 1
        }
        guard offset < ns.length else { return nil }
        let r = ns.lineRange(for: NSRange(location: offset, length: 0))
        // Trim the trailing newline so the underline hugs the code.
        let text = ns.substring(with: r).trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return nil }
        return NSRange(location: r.location, length: (text as NSString).length)
    }

    /// diagnosticID fragments → Chinese. Covers the errors users hit most.
    private static let idTranslations: [(String, String)] = [
        ("missingToken", "缺少符号"),
        ("unexpectedToken", "此处有多余的符号"),
        ("expectedExpression", "此处需要一个表达式"),
        ("expectedType", "此处需要一个类型"),
        ("expectedIdentifier", "此处需要一个标识符"),
        ("extraneousCode", "此处有多余的代码"),
        ("missingExpression", "缺少表达式"),
    ]

    private static let fragmentTranslations: [(String, String)] = [
        ("expected '}'", "缺少 '}'"),
        ("expected ')'", "缺少 ')'"),
        ("expected ']'", "缺少 ']'"),
        ("expected expression", "此处需要一个表达式"),
        ("expected identifier", "此处需要一个标识符"),
        ("unexpected code", "此处有多余的代码"),
        ("consecutive statements", "语句之间需要换行或分号"),
    ]
}
