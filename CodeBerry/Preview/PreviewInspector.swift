import Foundation
import SwiftSyntax
import SwiftParser
import SwiftUI

// MARK: - §三 Override model (preview-only adjustments)

/// A color value the Inspector can write back to source.
struct PreviewColorSpec: Equatable {
    /// Display name without dot, e.g. "red", "white".
    var name: String?
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    /// When set, the color comes from / writes to a design token (§六).
    var tokenName: String?

    static let palette: [(name: String, color: Color)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
        ("mint", .mint), ("teal", .teal), ("cyan", .cyan), ("blue", .blue),
        ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("brown", .brown),
        ("white", .white), ("gray", .gray), ("black", .black), ("primary", .primary),
        ("secondary", .secondary),
    ]

    func toColor() -> Color {
        if let name, let entry = Self.palette.first(where: { $0.name == name }) {
            return entry.color.opacity(opacity)
        }
        return Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    /// Swift source for this color.
    func toSource() -> String {
        if let tokenName { return tokenName }
        if let name { return ".\(name)" }
        return "Color(red: \(PreviewSourceEditor.fmt(red)), green: \(PreviewSourceEditor.fmt(green)), blue: \(PreviewSourceEditor.fmt(blue)), opacity: \(PreviewSourceEditor.fmt(opacity)))"
    }
}

let previewFontWeights = ["ultralight", "thin", "light", "regular", "medium",
                           "semibold", "bold", "heavy", "black"]

/// Per-node adjustable parameters (§三). Nil = not overridden.
struct PreviewNodeOverride: Equatable {
    var fontSize: Double?
    var fontWeight: String?
    var textColor: PreviewColorSpec?
    var lineLimit: Int?
    var stackSpacing: Double?
    var stackAlignment: String?
    var padding: Double?
    var width: Double?
    var height: Double?
    var minHeight: Double?
    var maxWidth: Double?
    var cornerRadius: Double?
    var opacity: Double?
    var fillColor: PreviewColorSpec?
    var strokeWidth: Double?

    var isEmpty: Bool {
        fontSize == nil && fontWeight == nil && textColor == nil && lineLimit == nil &&
        stackSpacing == nil && stackAlignment == nil && padding == nil &&
        width == nil && height == nil && minHeight == nil && maxWidth == nil &&
        cornerRadius == nil && opacity == nil && fillColor == nil && strokeWidth == nil
    }
}

/// Which params make sense for a node kind (§三: 不同元素可调参数不同).
enum PreviewInspectorParams {
    static func params(for node: PreviewViewNode) -> [PreviewParam] {
        switch node.kind {
        case .text, .label:
            return [.fontSize, .fontWeight, .textColor, .lineLimit, .padding,
                    .width, .height, .cornerRadius, .opacity]
        case .stack:
            return [.stackSpacing, .stackAlignment, .padding, .width, .height,
                    .minHeight, .maxWidth, .cornerRadius, .opacity]
        case .shape:
            return [.fillColor, .width, .height, .cornerRadius, .opacity]
        case .strokedShape:
            return [.strokeWidth, .width, .height, .opacity]
        case .image:
            return [.width, .height, .cornerRadius, .opacity]
        case .button:
            return [.textColor, .padding, .cornerRadius, .opacity, .width, .height]
        case .colorView:
            return [.cornerRadius, .opacity, .width, .height]
        default:
            return [.padding, .width, .height, .cornerRadius, .opacity]
        }
    }
}

enum PreviewParam: Hashable {
    case fontSize, fontWeight, textColor, lineLimit
    case stackSpacing, stackAlignment
    case padding, width, height, minHeight, maxWidth
    case cornerRadius, opacity, fillColor, strokeWidth

    var titleKey: L10nKey {
        switch self {
        case .fontSize: return .paramFontSize
        case .fontWeight: return .paramFontWeight
        case .textColor: return .paramTextColor
        case .lineLimit: return .paramLineLimit
        case .stackSpacing: return .paramSpacing
        case .stackAlignment: return .paramAlignment
        case .padding: return .paramPadding
        case .width: return .paramWidth
        case .height: return .paramHeight
        case .minHeight: return .paramMinHeight
        case .maxWidth: return .paramMaxWidth
        case .cornerRadius: return .paramCornerRadius
        case .opacity: return .paramOpacity
        case .fillColor: return .paramFillColor
        case .strokeWidth: return .paramStrokeWidth
        }
    }
}

// MARK: - Inspector state

/// Canvas-level inspector state: selection + preview-only overrides (§三).
@Observable
final class PreviewInspectorState {
    var selectedID: String?
    var overrides: [String: PreviewNodeOverride] = [:]
    /// Before/after snapshot (§十): file path → source at snapshot time.
    var snapshotSources: [String: String] = [:]

    func override(for node: PreviewViewNode) -> PreviewNodeOverride {
        guard let id = node.source?.nodeID else { return PreviewNodeOverride() }
        return overrides[id] ?? PreviewNodeOverride()
    }

    func setOverride(_ mutate: (inout PreviewNodeOverride) -> Void, for nodeID: String) {
        var o = overrides[nodeID] ?? PreviewNodeOverride()
        mutate(&o)
        if o.isEmpty {
            overrides.removeValue(forKey: nodeID)
        } else {
            overrides[nodeID] = o
        }
    }

    func clearOverride(for nodeID: String) {
        overrides.removeValue(forKey: nodeID)
    }

    func resetAll() {
        selectedID = nil
        overrides.removeAll()
    }

    /// Apply preview-only overrides to a node for rendering.
    func applied(to node: PreviewViewNode) -> PreviewViewNode {
        let o = override(for: node)
        guard !o.isEmpty else { return node }
        var node = node
        // Stack spacing / alignment mutate the kind itself.
        if case .stack(let axis, let alignment, let spacing, let children) = node.kind,
           o.stackSpacing != nil || o.stackAlignment != nil {
            node.kind = .stack(axis,
                               alignment: o.stackAlignment ?? alignment,
                               spacing: o.stackSpacing ?? spacing,
                               children: children)
        }
        // Stroke width mutates a stroked shape.
        if case .strokedShape(let kind, let color, _) = node.kind, let w = o.strokeWidth {
            node.kind = .strokedShape(kind, color, w)
        }
        // Everything else appends winning modifiers (later ops win).
        var ops: [PreviewModifierOp] = []
        if let v = o.fontSize { ops.append(.font(.system(size: v))) }
        if let w = o.fontWeight, let weight = PreviewInspectorState.fontWeight(named: w) {
            ops.append(.fontWeight(weight))
        }
        if let c = o.textColor { ops.append(.foreground(c.toColor())) }
        if let n = o.lineLimit { ops.append(.lineLimit(n)) }
        if let v = o.padding { ops.append(.padding(.all, v)) }
        if o.width != nil || o.height != nil || o.minHeight != nil || o.maxWidth != nil {
            ops.append(.frame(w: o.width, h: o.height, minW: nil, minH: o.minHeight,
                              maxW: o.maxWidth, maxH: nil, alignment: nil))
        }
        if let v = o.cornerRadius { ops.append(.cornerRadius(v)) }
        if let v = o.opacity { ops.append(.opacity(v)) }
        if let c = o.fillColor { ops.append(.background(c.toColor())) }
        node.modifiers.append(contentsOf: ops)
        return node
    }

    static func fontWeight(named name: String) -> Font.Weight? {
        switch name {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return nil
        }
    }
}

// MARK: - §三 Source editor (override → code)

/// Rewrites modifier arguments in Swift source via SwiftSyntax, range-based
/// (never fuzzy text search). All functions return nil when the range doesn't
/// cover a suitable expression — the caller then disables the control.
enum PreviewSourceEditor {
    enum Strategy { case outermostInRange, atRangeStart }

    // MARK: String ↔ UTF-8 offset helpers

    static func fmt(_ v: Double) -> String {
        if v.isInfinite { return v > 0 ? ".infinity" : "-.infinity" }
        if v == v.rounded(), abs(v) < 1_000_000_000 { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func index(_ source: String, at offset: Int) -> String.Index? {
        source.utf8.index(source.utf8.startIndex, offsetBy: offset,
                          limitedBy: source.utf8.endIndex)
            .flatMap { String.Index($0, within: source) }
    }

    private static func range(_ source: String, _ offsets: Range<Int>) -> Range<String.Index>? {
        guard let lo = index(source, at: offsets.lowerBound),
              let hi = index(source, at: offsets.upperBound) else { return nil }
        return lo..<hi
    }

    // MARK: Call finding

    private final class CallFinder: SyntaxVisitor {
        var calls: [FunctionCallExprSyntax] = []
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            calls.append(node)
            return .visitChildren
        }
    }

    static func callName(of call: FunctionCallExprSyntax) -> String? {
        let called = call.calledExpression
        if let member = called.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
        if let ref = called.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
        return nil
    }

    static func calls(in source: String, range: Range<Int>) -> [FunctionCallExprSyntax] {
        let tree = Parser.parse(source: source)
        let finder = CallFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.calls.filter { call in
            let start = call.positionAfterSkippingLeadingTrivia.utf8Offset
            let end = call.endPosition.utf8Offset
            return start >= range.lowerBound && end <= range.upperBound
        }
    }

    private static func targetCall(in source: String, range: Range<Int>,
                                   names: [String], strategy: Strategy) -> FunctionCallExprSyntax? {
        let cands = calls(in: source, range: range).filter { names.contains(callName(of: $0) ?? "") }
        switch strategy {
        case .outermostInRange:
            return cands.max(by: { $0.positionAfterSkippingLeadingTrivia.utf8Offset < $1.positionAfterSkippingLeadingTrivia.utf8Offset })
        case .atRangeStart:
            return cands.first { $0.positionAfterSkippingLeadingTrivia.utf8Offset == range.lowerBound }
        }
    }

    // MARK: Argument rewrite (atomic multi-param path above)

    // MARK: Param edits (§三: 点选调参 → 源码)

    /// One argument rewrite attempt on a call.
    struct ArgEdit {
        var callNames: [String]
        var strategy: Strategy = .outermostInRange
        var argLabel: String?
        var newArg: String
        var addIfMissing: Bool = true
        /// Instead of replacing the argument, transform its existing text
        /// (used for `.font(X)` → `.font(X.weight(.bold))`).
        var mapExisting: ((String) -> String)?
        /// When set, the argument is only replaced if this returns true for
        /// its current text (used for `.padding(.horizontal)` vs `.padding(16)`).
        var replaceOnlyIf: ((String) -> Bool)?
    }

    /// All attempts for one inspector param, in order. The first attempt
    /// whose call exists wins; otherwise `appendFallback` is appended.
    struct ParamEdit {
        var attempts: [ArgEdit]
        var appendFallback: String?
    }

    /// Apply several param edits atomically: single parse, surgeries applied
    /// end-to-start so offsets never go stale.
    static func applyParamEdits(_ params: [ParamEdit], source: String,
                                range: Range<Int>) -> String? {
        let tree = Parser.parse(source: source)
        let finder = CallFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        let inRange = finder.calls.filter { call in
            let start = call.positionAfterSkippingLeadingTrivia.utf8Offset
            return start >= range.lowerBound && call.endPosition.utf8Offset <= range.upperBound
        }
        struct Surgery { let offset: Int; let length: Int; let text: String; let seq: Int }
        var surgeries: [Surgery] = []
        var seq = 0

        func findTarget(_ edit: ArgEdit) -> FunctionCallExprSyntax? {
            let cands = inRange.filter { edit.callNames.contains(callName(of: $0) ?? "") }
            switch edit.strategy {
            case .outermostInRange:
                return cands.max(by: {
                    $0.positionAfterSkippingLeadingTrivia.utf8Offset < $1.positionAfterSkippingLeadingTrivia.utf8Offset
                })
            case .atRangeStart:
                return cands.first {
                    $0.positionAfterSkippingLeadingTrivia.utf8Offset == range.lowerBound
                }
            }
        }

        for param in params {
            var handled = false
            for attempt in param.attempts {
                guard let call = findTarget(attempt) else { continue }
                if let label = attempt.argLabel,
                   let arg = call.arguments.first(where: { $0.label?.text == label }) {
                    let expr = arg.expression
                    let start = expr.positionAfterSkippingLeadingTrivia.utf8Offset
                    let newText = attempt.mapExisting?(expr.trimmedDescription) ?? attempt.newArg
                    surgeries.append(Surgery(offset: start,
                                             length: expr.endPosition.utf8Offset - start,
                                             text: newText, seq: seq))
                    seq += 1
                    handled = true
                    break
                } else if attempt.argLabel == nil, let arg = call.arguments.first {
                    let expr = arg.expression
                    let currentText = expr.trimmedDescription
                    if let guardFn = attempt.replaceOnlyIf, !guardFn(currentText) {
                        // Not replaceable (e.g. `.padding(.horizontal)`) — fall
                        // through to the addIfMissing insert below.
                    } else {
                        let start = expr.positionAfterSkippingLeadingTrivia.utf8Offset
                        let newText = attempt.mapExisting?(currentText) ?? attempt.newArg
                        surgeries.append(Surgery(offset: start,
                                                 length: expr.endPosition.utf8Offset - start,
                                                 text: newText, seq: seq))
                        seq += 1
                        handled = true
                        break
                    }
                }
                if !handled, attempt.addIfMissing,
                          let insertion = insertionPoint(for: call, argLabel: attempt.argLabel,
                                                        newArg: attempt.newArg) {
                    surgeries.append(Surgery(offset: insertion, length: 0,
                                             text: insertionText(for: call, argLabel: attempt.argLabel,
                                                               newArg: attempt.newArg),
                                             seq: seq))
                    seq += 1
                    handled = true
                    break
                }
            }
            if !handled, let fallback = param.appendFallback {
                surgeries.append(Surgery(offset: range.upperBound, length: 0,
                                         text: fallback, seq: seq))
                seq += 1
            }
        }

        guard !surgeries.isEmpty else { return nil }
        // End-to-start; same-offset inserts apply in reverse param order so
        // the first param's text ends up first.
        let ordered = surgeries.sorted {
            if $0.offset != $1.offset { return $0.offset > $1.offset }
            return $0.seq > $1.seq
        }
        var result = source
        for s in ordered {
            guard let lo = index(result, at: s.offset),
                  let hi = index(result, at: s.offset + s.length) else { return nil }
            result.replaceSubrange(lo..<hi, with: s.text)
        }
        return result
    }

    private static func insertionPoint(for call: FunctionCallExprSyntax,
                                       argLabel: String?, newArg: String) -> Int? {
        if let rightParen = call.rightParen, call.leftParen != nil {
            if call.arguments.isEmpty { return call.leftParen!.endPosition.utf8Offset }
            return rightParen.positionAfterSkippingLeadingTrivia.utf8Offset
        }
        if let closure = call.trailingClosure {
            return closure.positionAfterSkippingLeadingTrivia.utf8Offset
        }
        return nil
    }

    private static func insertionText(for call: FunctionCallExprSyntax,
                                      argLabel: String?, newArg: String) -> String {
        let text = argLabel.map { "\($0): \(newArg)" } ?? newArg
        if call.leftParen != nil {
            return call.arguments.isEmpty ? text : ", \(text)"
        }
        // Trailing-closure-only call: add parens before the closure.
        return "(\(text)) "
    }

    // MARK: Param edit builders (one ParamEdit per inspector param)

    static func editFontSize(_ size: Double) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["system"], argLabel: "size", newArg: fmt(size)),
            ArgEdit(callNames: ["font"], argLabel: nil, newArg: ".system(size: \(fmt(size)))"),
        ], appendFallback: ".font(.system(size: \(fmt(size))))")
    }

    static func editFontWeight(_ weight: String) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["weight"], argLabel: nil, newArg: ".\(weight)"),
            ArgEdit(callNames: ["font"], argLabel: nil, newArg: "",
                    mapExisting: { "\($0).weight(.\(weight))" }),
        ], appendFallback: ".fontWeight(.\(weight))")
    }

    static func editTextColor(_ color: String) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["foregroundStyle", "foregroundColor"],
                    argLabel: nil, newArg: color),
        ], appendFallback: ".foregroundStyle(\(color))")
    }

    static func editLineLimit(_ limit: Int) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["lineLimit"], argLabel: nil, newArg: String(limit)),
        ], appendFallback: ".lineLimit(\(limit))")
    }

    static func editPadding(_ amount: Double) -> ParamEdit {
        // `.padding(16)`: replace the number. `.padding(.horizontal)`:
        // keep the edges, insert the amount.
        ParamEdit(attempts: [
            ArgEdit(callNames: ["padding"], argLabel: nil, newArg: fmt(amount),
                    replaceOnlyIf: { Double($0) != nil }),
        ], appendFallback: ".padding(\(fmt(amount)))")
    }

    static func editFrame(label: String, value: Double) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["frame"], argLabel: label, newArg: fmt(value)),
        ], appendFallback: ".frame(\(label): \(fmt(value)))")
    }

    static func editCornerRadius(_ radius: Double) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["cornerRadius"], argLabel: nil, newArg: fmt(radius)),
        ], appendFallback: ".cornerRadius(\(fmt(radius)))")
    }

    static func editOpacity(_ opacity: Double) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["opacity"], argLabel: nil, newArg: fmt(opacity)),
        ], appendFallback: ".opacity(\(fmt(opacity)))")
    }

    static func editFillColor(_ color: String) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["background"], argLabel: nil, newArg: color),
        ], appendFallback: ".background(\(color))")
    }

    static func editStrokeWidth(_ width: Double) -> ParamEdit {
        // Only when a stroke call already exists — no blind appends.
        ParamEdit(attempts: [
            ArgEdit(callNames: ["stroke", "strokeBorder"],
                    argLabel: "lineWidth", newArg: fmt(width)),
        ], appendFallback: nil)
    }

    static func editStackSpacing(_ spacing: Double) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["VStack", "HStack", "ZStack"], strategy: .atRangeStart,
                    argLabel: "spacing", newArg: fmt(spacing)),
        ], appendFallback: nil)
    }

    static func editStackAlignment(_ alignment: String) -> ParamEdit {
        ParamEdit(attempts: [
            ArgEdit(callNames: ["VStack", "HStack", "ZStack"], strategy: .atRangeStart,
                    argLabel: "alignment", newArg: ".\(alignment)"),
        ], appendFallback: nil)
    }

    // MARK: Single-param conveniences (also used by tests)

    static func setFontSize(source: String, range: Range<Int>, size: Double) -> String? {
        applyParamEdits([editFontSize(size)], source: source, range: range)
    }

    static func setFontWeight(source: String, range: Range<Int>, weight: String) -> String? {
        applyParamEdits([editFontWeight(weight)], source: source, range: range)
    }

    static func setTextColor(source: String, range: Range<Int>, color: String) -> String? {
        applyParamEdits([editTextColor(color)], source: source, range: range)
    }

    static func setLineLimit(source: String, range: Range<Int>, limit: Int) -> String? {
        applyParamEdits([editLineLimit(limit)], source: source, range: range)
    }

    static func setPadding(source: String, range: Range<Int>, amount: Double) -> String? {
        applyParamEdits([editPadding(amount)], source: source, range: range)
    }

    static func setFrame(source: String, range: Range<Int>,
                         label: String, value: Double) -> String? {
        applyParamEdits([editFrame(label: label, value: value)], source: source, range: range)
    }

    static func setCornerRadius(source: String, range: Range<Int>, radius: Double) -> String? {
        applyParamEdits([editCornerRadius(radius)], source: source, range: range)
    }

    static func setOpacity(source: String, range: Range<Int>, opacity: Double) -> String? {
        applyParamEdits([editOpacity(opacity)], source: source, range: range)
    }

    static func setFillColor(source: String, range: Range<Int>, color: String) -> String? {
        applyParamEdits([editFillColor(color)], source: source, range: range)
    }

    static func setStrokeWidth(source: String, range: Range<Int>, width: Double) -> String? {
        applyParamEdits([editStrokeWidth(width)], source: source, range: range)
    }

    static func setStackSpacing(source: String, range: Range<Int>, spacing: Double) -> String? {
        applyParamEdits([editStackSpacing(spacing)], source: source, range: range)
    }

    static func setStackAlignment(source: String, range: Range<Int>, alignment: String) -> String? {
        applyParamEdits([editStackAlignment(alignment)], source: source, range: range)
    }

    // MARK: Reading current values + token provenance (§六)

    /// The trimmed argument text of a modifier call in the range, e.g. the
    /// `16` in `.padding(16)` or `V32Layout.gap`.
    static func argumentText(source: String, range: Range<Int>,
                             callNames: [String], argLabel: String? = nil) -> String? {
        guard let call = targetCall(in: source, range: range, names: callNames,
                                    strategy: .outermostInRange) else { return nil }
        let arg: LabeledExprSyntax?
        if let label = argLabel {
            arg = call.arguments.first(where: { $0.label?.text == label })
        } else {
            arg = call.arguments.first
        }
        return arg?.expression.trimmedDescription
    }

    /// Rewrite a token's `let` declaration to a new value expression.
    /// Uses the declaration offsets recorded at index time (§六).
    static func rewriteToken(source: String, token: PreviewToken, newValueSource: String) -> String? {
        let offsets = token.declStartOffset..<token.declEndOffset
        guard let r = range(source, offsets) else { return nil }
        let declText = String(source[r])
        // Replace just the initializer: `let name = <old>` → `let name = <new>`.
        guard let eq = declText.firstIndex(of: "=") else { return nil }
        let head = declText[..<eq]
        return source.replacingCharacters(in: r, with: "\(head)= \(newValueSource)")
    }
}
