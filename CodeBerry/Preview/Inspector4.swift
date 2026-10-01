import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - M3 §18 Inspector 4.0
//
// On top of the 3.0 inspector:
//   - modifier reorder (safe subset only — cosmetic/layout modifiers, no
//     trailing closures, adjacent swaps only)
//   - token-aware: detect `V32Layout.sectionGap`-style references, show
//     "来自设计令牌 X", and show the estimated reference count before a
//     token definition is edited
//   - reset one param / reset element (element reset exists in 3.0)
//   - jump to code (wired in the canvas via PreviewSelection)
//
// Diff-before-apply, preview-only override and tap-to-select already exist
// in 3.0 and are reused unchanged.

extension PreviewInspectorState {
    /// §18 "reset one param": clear a single param's override, keep the rest.
    func resetParam(_ param: PreviewParam, for nodeID: String) {
        setOverride({ o in
            switch param {
            case .fontSize: o.fontSize = nil
            case .fontWeight: o.fontWeight = nil
            case .textColor: o.textColor = nil
            case .lineLimit: o.lineLimit = nil
            case .stackSpacing: o.stackSpacing = nil
            case .stackAlignment: o.stackAlignment = nil
            case .padding: o.padding = nil
            case .width: o.width = nil
            case .height: o.height = nil
            case .minHeight: o.minHeight = nil
            case .maxWidth: o.maxWidth = nil
            case .cornerRadius: o.cornerRadius = nil
            case .opacity: o.opacity = nil
            case .fillColor: o.fillColor = nil
            case .strokeWidth: o.strokeWidth = nil
            }
        }, for: nodeID)
    }
}

// MARK: - Modifier reorder (safe subset)

extension PreviewSourceEditor {
    /// Modifiers that are safe to reorder: pure cosmetic/layout, no closures,
    /// no view-builder trailing closures. Anything else → nil (control
    /// disabled in the UI).
    static let reorderSafeModifiers: Set<String> = [
        "padding", "font", "fontWeight", "bold", "italic",
        "foregroundColor", "foregroundStyle", "background", "tint",
        "frame", "cornerRadius", "clipShape", "opacity", "shadow",
        "lineLimit", "multilineTextAlignment",
    ]

    /// Modifier names in the node's range, outermost-first
    /// (e.g. `Text("a").padding(8).font(.title)` → ["font", "padding"]).
    /// Returns nil when the range doesn't cover a member-access call chain.
    static func modifierChain(in source: String, range: Range<Int>) -> [String]? {
        guard let (calls, _) = modifierCalls(in: source, range: range),
              !calls.isEmpty else { return nil }
        return calls.map { callName(of: $0) ?? "?" }
    }

    /// Swap two ADJACENT modifiers (`to` must be `from ± 1`).
    /// Returns the new source, or nil when unsafe / not found.
    static func reorderModifiers(source: String, range: Range<Int>,
                                from: Int, to: Int) -> String? {
        guard abs(to - from) == 1 else { return nil }
        guard let (calls, base) = modifierCalls(in: source, range: range) else { return nil }
        let i = min(from, to)
        guard i >= 0, i + 1 < calls.count else { return nil }
        let names = calls.map { callName(of: $0) ?? "?" }
        guard reorderSafeModifiers.contains(names[i]),
              reorderSafeModifiers.contains(names[i + 1]) else { return nil }
        // No trailing closures — moving a view-builder would change semantics.
        for c in [calls[i], calls[i + 1]] {
            if c.trailingClosure != nil || !c.additionalTrailingClosures.isEmpty { return nil }
        }

        // Rebuild inside-out with the two calls swapped.
        var order = calls
        order.swapAt(i, i + 1)
        var expr: ExprSyntax = base
        for call in order.reversed() {
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
            let newMember = member.with(\.base, Optional(expr))
            let rebuilt = call.with(\.calledExpression, ExprSyntax(newMember))
            expr = ExprSyntax(rebuilt)
        }
        let outer = calls[0]
        let start = outer.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = outer.endPosition.utf8Offset
        // Convert UTF-8 offsets to String indices safely.
        guard let lo = utf8Index(start, in: source), let hi = utf8Index(end, in: source) else { return nil }
        var out = source
        // trimmedDescription: outermost leading trivia stays in place (the
        // range starts after it); inner calls keep their own trivia.
        out.replaceSubrange(lo..<hi, with: expr.trimmedDescription)
        return out
    }

    // MARK: - internals

    /// Outermost-first modifier calls + the base expression they wrap.
    private static func modifierCalls(in source: String, range: Range<Int>)
        -> (calls: [FunctionCallExprSyntax], base: ExprSyntax)? {
        let tree = Parser.parse(source: source)
        let finder = CallCollector(viewMode: .sourceAccurate)
        finder.walk(tree)
        let inRange = finder.calls.filter { call in
            let start = call.positionAfterSkippingLeadingTrivia.utf8Offset
            return start >= range.lowerBound && call.endPosition.utf8Offset <= range.upperBound
        }
        // Outermost = largest span in range.
        guard let outer = inRange.max(by: {
            span($0) < span($1)
        }) else { return nil }
        var calls: [FunctionCallExprSyntax] = []
        var cur: ExprSyntax = ExprSyntax(outer)
        while let call = cur.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base {
            calls.append(call)
            cur = base
        }
        guard !calls.isEmpty else { return nil }
        return (calls, cur)
    }

    private static func span(_ call: FunctionCallExprSyntax) -> Int {
        call.endPosition.utf8Offset - call.positionAfterSkippingLeadingTrivia.utf8Offset
    }

    private static func utf8Index(_ offset: Int, in source: String) -> String.Index? {
        guard offset >= 0 else { return nil }
        guard let idx = source.utf8.index(source.utf8.startIndex, offsetBy: offset,
                                              limitedBy: source.utf8.endIndex) else { return nil }
        return String.Index(idx, within: source)
    }

    private final class CallCollector: SyntaxVisitor {
        var calls: [FunctionCallExprSyntax] = []
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            calls.append(node)
            return .visitChildren
        }
    }
}

// MARK: - Token awareness (§18)

/// Detects design-token references (`V32Layout.sectionGap`) in a value
/// expression so the inspector can show "来自设计令牌 X" and warn with the
/// estimated reference count before the token definition is edited.
enum DesignTokenDetector {
    /// Returns the token reference (e.g. "V32Layout.sectionGap") when
    /// `exprText` is/contains one. `knownTokens` comes from ProjectAnalyzer;
    /// when empty, a conservative naming heuristic applies.
    static func tokenReference(in exprText: String, knownTokens: Set<String>) -> String? {
        let pattern = #"\b([A-Z][A-Za-z0-9_]*)\.([a-zA-Z][A-Za-z0-9_]*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = exprText as NSString
        for m in regex.matches(in: exprText, range: NSRange(location: 0, length: ns.length)) {
            let typeName = ns.substring(with: m.range(at: 1))
            let member = ns.substring(with: m.range(at: 2))
            // Skip well-known framework types.
            if ["Color", "Font", "Material", "CGFloat", "Double", "Int", "String"].contains(typeName) { continue }
            let ref = "\(typeName).\(member)"
            if knownTokens.contains(ref) { return ref }
            if knownTokens.isEmpty && isTokenish(typeName) { return ref }
        }
        return nil
    }

    private static func isTokenish(_ typeName: String) -> Bool {
        typeName.hasPrefix("V32") || typeName.hasPrefix("DS")
            || ["Tokens", "Token", "Layout", "Colors", "Typography", "Spacing", "Radius", "Shadows"]
                .contains(where: { typeName.hasSuffix($0) })
    }

    /// §18: "修改 token 前显示预计引用数" — counts whole-token occurrences
    /// across the given file contents (word-boundary match).
    static func referenceCount(of token: String, in fileContents: [String]) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        guard let regex = try? NSRegularExpression(pattern: #"\b"# + escaped + #"\b"#) else { return 0 }
        return fileContents.reduce(0) { acc, text in
            acc + regex.numberOfMatches(in: text,
                                        range: NSRange(location: 0, length: (text as NSString).length))
        }
    }
}
