import SwiftUI
import SwiftSyntax
import Observation

// MARK: - Runtime values

indirect enum PreviewValue {
    case number(Double)
    case string(String)
    case bool(Bool)
    case array([PreviewValue])
    case range(Int, Int, inclusive: Bool)
    case color(Color)
    case font(Font)
    case view(PreviewViewNode)
    case binding(String)
    case member(String)
    case void

    var doubleValue: Double? {
        if case .number(let v) = self { return v }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// String form used for interpolation ("Count: \(count)").
    var display: String {
        switch self {
        case .number(let v):
            return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return "[" + a.map(\.display).joined(separator: ", ") + "]"
        case .member(let m): return "." + m
        default: return ""
        }
    }
}

/// Backing store for interpreted `@State` properties. Bumping `version`
/// invalidates the canvas, which re-evaluates the body — the same
/// state-driven render loop SwiftUI itself runs.
@Observable
final class PreviewRuntime {
    private(set) var version = 0
    private var storage: [String: PreviewValue] = [:]

    func value(_ key: String) -> PreviewValue? { storage[key] }

    func set(_ key: String, _ value: PreviewValue) {
        storage[key] = value
        version += 1
    }

    /// Initialize state without invalidating (used while rendering).
    func seed(_ key: String, _ value: PreviewValue) {
        storage[key] = value
    }

    func resetAll() {
        storage = [:]
        version += 1
    }

    func boolValue(_ key: String, fallback: Bool = false) -> Bool { storage[key]?.boolValue ?? fallback }
    func stringValue(_ key: String) -> String { storage[key]?.display ?? "" }
    func doubleValue(_ key: String, fallback: Double = 0) -> Double { storage[key]?.doubleValue ?? fallback }
}

// MARK: - Evaluator

/// Walks the parsed syntax tree and produces `PreviewViewNode`s. Anything it
/// doesn't understand becomes a warning chip instead of a crash.
final class PreviewEvaluator {
    struct Env {
        var typeName = ""
        var locals: [String: PreviewValue] = [:]
        var stateKeys: [String: String] = [:]
    }

    let doc: PreviewDocument
    let runtime: PreviewRuntime
    private(set) var warnings: [String] = []
    private var warningSet: Set<String> = []
    private var depth = 0

    init(doc: PreviewDocument, runtime: PreviewRuntime) {
        self.doc = doc
        self.runtime = runtime
    }

    func renderRoot() throws -> [PreviewViewNode] {
        if let previewBody = doc.previewBody {
            return try viewBuilderChildren(previewBody, env: Env())
        }
        guard let firstName = doc.viewOrder.first, let first = doc.views[firstName] else {
            throw PreviewError(message: "No SwiftUI view found in this file.")
        }
        return [try instantiateStruct(first, args: [], callerEnv: Env())]
    }

    func warn(_ message: String) {
        guard !warningSet.contains(message) else { return }
        warningSet.insert(message)
        warnings.append(message)
    }

    // MARK: Struct instantiation

    func instantiateStruct(_ viewStruct: PreviewViewStruct,
                             args: [(label: String?, expr: ExprSyntax)],
                             callerEnv: Env) throws -> PreviewViewNode {
        depth += 1
        defer { depth -= 1 }
        guard depth < 40 else {
            throw PreviewError(message: "View nesting too deep (recursive view?).")
        }

        var env = Env(typeName: viewStruct.name)
        for property in viewStruct.properties {
            if property.isState {
                let key = "\(viewStruct.name).\(property.name)"
                env.stateKeys[property.name] = key
                if runtime.value(key) == nil, let initial = property.initialValue {
                    runtime.seed(key, try eval(initial, env: env))
                }
            } else if let arg = args.first(where: { $0.label == property.name }) {
                env.locals[property.name] = try eval(arg.expr, env: callerEnv)
            } else if let initial = property.initialValue {
                env.locals[property.name] = try eval(initial, env: env)
            }
        }

        guard let body = viewStruct.bodyStatements else {
            throw PreviewError(message: "\(viewStruct.name) has no body to preview.")
        }
        let children = try viewBuilderChildren(body, env: env)
        if children.count == 1 { return children[0] }
        return PreviewViewNode(kind: .stack(.vertical, alignment: nil, spacing: 8, children: children))
    }

    // MARK: View builders

    func viewBuilderChildren(_ statements: CodeBlockItemListSyntax, env: Env) throws -> [PreviewViewNode] {
        var env = env
        var out: [PreviewViewNode] = []
        for item in statements {
            switch item.item {
            case .decl(let decl):
                guard let variable = decl.as(VariableDeclSyntax.self) else {
                    warn("Declarations inside body aren't supported: \(snippet(decl))")
                    continue
                }
                for binding in variable.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                       let initializer = binding.initializer {
                        env.locals[pattern.identifier.text] = try eval(initializer.value, env: env)
                    }
                }
            case .stmt(let stmt):
                if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                    out += try viewNodes(from: exprStmt.expression, env: env)
                }
            case .expr(let expr):
                out += try viewNodes(from: expr, env: env)
            }
        }
        return out
    }

    private func viewNodes(from expr: ExprSyntax, env: Env) throws -> [PreviewViewNode] {
        if let ifExpr = expr.as(IfExprSyntax.self) {
            return try evalIf(ifExpr, env: env)
        }
        let value = try eval(expr, env: env)
        switch value {
        case .view(let node): return [node]
        case .color(let color): return [PreviewViewNode(kind: .colorView(color))]
        case .void: return []
        default:
            warn("Expression isn't a view: \(snippet(expr))")
            return []
        }
    }

    private func evalIf(_ ifExpr: IfExprSyntax, env: Env) throws -> [PreviewViewNode] {
        guard let firstCondition = ifExpr.conditions.first,
              case .expression(let condition) = firstCondition.condition else {
            warn("`if let` / `if case` aren't supported in previews yet.")
            return []
        }
        let isTrue = (try eval(condition, env: env)).boolValue ?? false
        if isTrue {
            return try viewBuilderChildren(ifExpr.body.statements, env: env)
        }
        switch ifExpr.elseBody {
        case .codeBlock(let block): return try viewBuilderChildren(block.statements, env: env)
        case .ifExpr(let nested): return try evalIf(nested, env: env)
        case nil: return []
        }
    }

    // MARK: Expression evaluation

    func eval(_ expr: ExprSyntax, env: Env) throws -> PreviewValue {
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            return .string(try interpolated(literal, env: env))
        }
        if let literal = expr.as(IntegerLiteralExprSyntax.self) {
            return .number(Double(literal.literal.text.replacingOccurrences(of: "_", with: "")) ?? 0)
        }
        if let literal = expr.as(FloatLiteralExprSyntax.self) {
            return .number(Double(literal.literal.text.replacingOccurrences(of: "_", with: "")) ?? 0)
        }
        if let literal = expr.as(BooleanLiteralExprSyntax.self) {
            return .bool(literal.literal.text == "true")
        }
        if expr.is(NilLiteralExprSyntax.self) { return .void }
        if expr.is(KeyPathExprSyntax.self) { return .member("keyPath") }
        if let tuple = expr.as(TupleExprSyntax.self), let first = tuple.elements.first {
            return try eval(first.expression, env: env)
        }
        if let array = expr.as(ArrayExprSyntax.self) {
            return .array(try array.elements.map { try eval($0.expression, env: env) })
        }
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            return evalReference(reference.baseName.text, env: env)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return try evalMember(member, env: env)
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return try evalCall(call, env: env)
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self) {
            let value = try eval(prefix.expression, env: env)
            switch prefix.operator.text {
            case "!": return .bool(!(value.boolValue ?? false))
            case "-": return .number(-(value.doubleValue ?? 0))
            default: break
            }
        }
        if let ternary = expr.as(TernaryExprSyntax.self) {
            let condition = (try eval(ternary.condition, env: env)).boolValue ?? false
            return try eval(condition ? ternary.thenExpression : ternary.elseExpression, env: env)
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self) {
            return try evalInfix(infix, env: env)
        }
        if let ifExpr = expr.as(IfExprSyntax.self) {
            let nodes = try evalIf(ifExpr, env: env)
            if nodes.count == 1 { return .view(nodes[0]) }
            return .view(PreviewViewNode(kind: .group(nodes)))
        }
        warn("Expression not supported: \(snippet(expr))")
        return .void
    }

    private func evalReference(_ name: String, env: Env) -> PreviewValue {
        if name.hasPrefix("$") {
            let property = String(name.dropFirst())
            if let key = env.stateKeys[property] { return .binding(key) }
            warn("$\(property) isn't a @State property.")
            return .void
        }
        if let local = env.locals[name] { return local }
        if let key = env.stateKeys[name] { return runtime.value(key) ?? .void }
        warn("Unknown identifier '\(name)'.")
        return .void
    }

    private func evalMember(_ member: MemberAccessExprSyntax, env: Env) throws -> PreviewValue {
        let name = member.declName.baseName.text
        guard let base = member.base else { return .member(name) }

        if let reference = base.as(DeclReferenceExprSyntax.self) {
            switch reference.baseName.text {
            case "Color":
                if let color = Self.colorTable[name] { return .color(color) }
            case "Font":
                if let font = Self.fontTable[name] { return .font(font) }
            case "Double", "CGFloat", "Float":
                if name == "infinity" { return .number(.infinity) }
                if name == "pi" { return .number(.pi) }
            default:
                break
            }
        }

        let baseValue = try eval(base, env: env)
        switch (baseValue, name) {
        case (.string(let s), "count"): return .number(Double(s.count))
        case (.string(let s), "isEmpty"): return .bool(s.isEmpty)
        case (.array(let a), "count"): return .number(Double(a.count))
        case (.array(let a), "isEmpty"): return .bool(a.isEmpty)
        case (.color(let c), "gradient"): return .color(c)   // close enough for a preview
        case (.member, _): return .member(name)
        default:
            warn("Member '.\(name)' not supported here.")
            return .void
        }
    }

    private func evalInfix(_ infix: InfixOperatorExprSyntax, env: Env) throws -> PreviewValue {
        let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            ?? (infix.operator.is(AssignmentExprSyntax.self) ? "=" : "?")
        let lhs = try eval(infix.leftOperand, env: env)
        if op == "??" {
            if case .void = lhs { return try eval(infix.rightOperand, env: env) }
            return lhs
        }
        let rhs = try eval(infix.rightOperand, env: env)

        switch op {
        case "+":
            if case .string(let l) = lhs { return .string(l + rhs.display) }
            if case .string(let r) = rhs { return .string(lhs.display + r) }
            return .number((lhs.doubleValue ?? 0) + (rhs.doubleValue ?? 0))
        case "-": return .number((lhs.doubleValue ?? 0) - (rhs.doubleValue ?? 0))
        case "*": return .number((lhs.doubleValue ?? 0) * (rhs.doubleValue ?? 0))
        case "/":
            let divisor = rhs.doubleValue ?? 1
            return .number(divisor == 0 ? 0 : (lhs.doubleValue ?? 0) / divisor)
        case "%":
            let divisor = rhs.doubleValue ?? 1
            return .number(divisor == 0 ? 0 : (lhs.doubleValue ?? 0).truncatingRemainder(dividingBy: divisor))
        case "==": return .bool(lhs.display == rhs.display)
        case "!=": return .bool(lhs.display != rhs.display)
        case "<": return .bool((lhs.doubleValue ?? 0) < (rhs.doubleValue ?? 0))
        case "<=": return .bool((lhs.doubleValue ?? 0) <= (rhs.doubleValue ?? 0))
        case ">": return .bool((lhs.doubleValue ?? 0) > (rhs.doubleValue ?? 0))
        case ">=": return .bool((lhs.doubleValue ?? 0) >= (rhs.doubleValue ?? 0))
        case "&&": return .bool((lhs.boolValue ?? false) && (rhs.boolValue ?? false))
        case "||": return .bool((lhs.boolValue ?? false) || (rhs.boolValue ?? false))
        case "..<": return .range(Int(lhs.doubleValue ?? 0), Int(rhs.doubleValue ?? 0), inclusive: false)
        case "...": return .range(Int(lhs.doubleValue ?? 0), Int(rhs.doubleValue ?? 0), inclusive: true)
        default:
            warn("Operator '\(op)' not supported.")
            return .void
        }
    }

    private func interpolated(_ literal: StringLiteralExprSyntax, env: Env) throws -> String {
        var out = ""
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let s):
                out += Self.unescape(s.content.text)
            case .expressionSegment(let e):
                for labeled in e.expressions {
                    out += (try eval(labeled.expression, env: env)).display
                }
            }
        }
        return out
    }

    private static func unescape(_ text: String) -> String {
        var out = ""
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            guard c == "\\" else { out.append(c); continue }
            switch iterator.next() {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            case "\\": out.append("\\")
            case "\"": out.append("\"")
            case "'": out.append("'")
            case let other?: out.append(other)
            case nil: break
            }
        }
        return out
    }

    // MARK: Action execution (button taps, etc.)

    func makeAction(_ closure: ClosureExprSyntax, env: Env) -> () -> Void {
        { [self] in execute(closure.statements, env: env) }
    }

    private func execute(_ statements: CodeBlockItemListSyntax, env: Env) {
        for item in statements {
            let expr: ExprSyntax?
            switch item.item {
            case .expr(let e): expr = e
            case .stmt(let s): expr = s.as(ExpressionStmtSyntax.self)?.expression
            case .decl: expr = nil
            }
            if let expr { executeExpr(expr, env: env) }
        }
    }

    private func executeExpr(_ expr: ExprSyntax, env: Env) {
        if let infix = expr.as(InfixOperatorExprSyntax.self) {
            let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
                ?? (infix.operator.is(AssignmentExprSyntax.self) ? "=" : "?")
            guard ["=", "+=", "-=", "*=", "/="].contains(op),
                  let lhs = infix.leftOperand.as(DeclReferenceExprSyntax.self),
                  let key = env.stateKeys[lhs.baseName.text] else {
                warn("Action not supported: \(snippet(expr))")
                return
            }
            let rhs = (try? eval(infix.rightOperand, env: env)) ?? .number(0)
            if op == "=" {
                runtime.set(key, rhs)
                return
            }
            if op == "+=", case .string(let suffix) = rhs {
                runtime.set(key, .string(runtime.stringValue(key) + suffix))
                return
            }
            let current = runtime.doubleValue(key)
            let operand = rhs.doubleValue ?? 0
            let result: Double = switch op {
            case "+=": current + operand
            case "-=": current - operand
            case "*=": current * operand
            default: operand == 0 ? current : current / operand
            }
            runtime.set(key, .number(result))
            return
        }

        if let call = expr.as(FunctionCallExprSyntax.self) {
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "toggle",
               let base = member.base?.as(DeclReferenceExprSyntax.self),
               let key = env.stateKeys[base.baseName.text] {
                runtime.set(key, .bool(!runtime.boolValue(key)))
                return
            }
            if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                if reference.baseName.text == "withAnimation", let trailing = call.trailingClosure {
                    execute(trailing.statements, env: env)
                    return
                }
                if reference.baseName.text == "print" { return }
            }
        }

        warn("Action not supported: \(snippet(expr))")
    }

    private func snippet(_ node: some SyntaxProtocol) -> String {
        let text = node.trimmedDescription
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    // MARK: Lookup tables

    static let colorTable: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green,
        "mint": .mint, "teal": .teal, "cyan": .cyan, "blue": .blue,
        "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
        "white": .white, "gray": .gray, "black": .black, "clear": .clear,
        "primary": .primary, "secondary": .secondary, "accentColor": .accentColor
    ]

    static let fontTable: [String: Font] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2,
        "title3": .title3, "headline": .headline, "subheadline": .subheadline,
        "body": .body, "callout": .callout, "footnote": .footnote,
        "caption": .caption, "caption2": .caption2
    ]

    static let weightTable: [String: Font.Weight] = [
        "ultraLight": .ultraLight, "thin": .thin, "light": .light,
        "regular": .regular, "medium": .medium, "semibold": .semibold,
        "bold": .bold, "heavy": .heavy, "black": .black
    ]
}
