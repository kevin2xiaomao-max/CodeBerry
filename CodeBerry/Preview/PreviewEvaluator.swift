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
    /// 4.0.2 P0-3: a safely-stubbed instance of a known cross-file type
    /// (e.g. `DemoMode.shared`). Never executes real code; member access
    /// resolves to preview defaults from declared type annotations.
    case typeStub(String)
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
        case .typeStub(let t): return t
        default: return ""
        }
    }

    /// True when the probe evaluator couldn't really build this value (e.g. a
    /// `Type()` init call that fell through to `.unsupported`, or `.void`).
    /// 4.0.2 P0-3: such statics stay opaque instead of pretending to have a value.
    var isUnevaluatedPlaceholder: Bool {
        if case .view(let node) = self, case .unsupported = node.kind { return true }
        if case .void = self { return true }
        return false
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
    /// §二 Cross-file index. When set, View/function/computed-view and token
    /// lookups span the whole project; the current document always wins.
    var projectIndex: PreviewProjectIndex?

    /// All Views visible to this evaluation: project index first, current
    /// document overriding ("当前文件的定义优先").
    var activeViews: [String: PreviewViewStruct] {
        guard let index = projectIndex else { return doc.views }
        var merged: [String: PreviewViewStruct] = [:]
        for (name, entry) in index.viewsByName { merged[name] = entry.view }
        for (name, view) in doc.views { merged[name] = view }
        return merged
    }
    /// 4.0.2 P0-3: all ordinary types visible to this evaluation — current
    /// document first, then the project index.
    var activeTypes: [String: PreviewTypeInfo] {
        var merged = projectIndex?.typesByName ?? [:]
        for (name, info) in doc.types { merged[name] = info }
        return merged
    }
    /// 4.0.2 P0-3: preview default for a declared type name. Never executes
    /// user code (no `didSet`, no initializers, no UserDefaults).
    static func previewDefault(forTypeName typeName: String) -> PreviewValue {
        switch typeName {
        case "Bool": return .bool(false)
        case "String": return .string("")
        case "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return .number(0)
        case "Double", "Float", "CGFloat", "Decimal": return .number(0)
        case "Date": return .string("")
        case let t where t.hasPrefix("[") || t.hasPrefix("Array"): return .array([])
        case let t where t.hasPrefix("Optional"): return .void
        default: return .void
        }
    }
    var warnings: [String] {
        diagnostics.filter { $0.severity == .warning }.map(\.message)
    }
    /// Structured diagnostics (§十一) — each has severity, message, file, line, API.
    private(set) var diagnostics: [PreviewDiagnostic] = []
    private var diagnosticSet: Set<String> = []
    /// Source location context for diagnostics: set by the canvas/index per file.
    var fileName: String = ""
    var converter: SourceLocationConverter?
    /// §七 Mock data store, set by the canvas.
    var mockStore: PreviewMockStore?

    /// §三 Source info for a syntax node (nil when no converter is set).
    func sourceInfo(for node: some SyntaxProtocol) -> PreviewSourceInfo? {
        guard let converter else { return nil }
        let pos = node.positionAfterSkippingLeadingTrivia
        return PreviewSourceInfo(file: fileName,
                                 line: converter.location(for: pos).line,
                                 startOffset: pos.utf8Offset,
                                 endOffset: node.endPosition.utf8Offset)
    }
    /// Recursion guard shared with PreviewEvaluator+Calls (computed views,
    /// helper functions, struct instantiation).
    var depth = 0

    init(doc: PreviewDocument, runtime: PreviewRuntime) {
        self.doc = doc
        self.runtime = runtime
    }

    func renderRoot() throws -> [PreviewViewNode] {
        if let previewBody = doc.previewBody {
            return try viewBuilderChildren(previewBody, env: Env())
        }
        guard let firstName = doc.viewOrder.first, let first = activeViews[firstName] else {
            throw PreviewError(.errNoPreviewableView)
        }
        return [try instantiateStruct(first, args: [], callerEnv: Env())]
    }

    /// Structured diagnostic (§十一): severity + localized message + file + line + API.
    func diagnose(_ severity: PreviewDiagnosticSeverity,
                  _ key: L10nKey,
                  params: [String] = [],
                  api: String? = nil,
                  node: (any SyntaxProtocol)? = nil,
                  file: String? = nil) {
        let line: Int?
        if let node, let converter {
            line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        } else {
            line = nil
        }
        let fileName = file ?? self.fileName
        // De-duplicate identical diagnostics so one repeated pattern doesn't
        // flood the panel.
        let dedupeKey = "\(severity)|\(key.rawValue)|\(params.joined(separator: "|"))|\(fileName)|\(line ?? -1)"
        guard !diagnosticSet.contains(dedupeKey) else { return }
        diagnosticSet.insert(dedupeKey)
        diagnostics.append(PreviewDiagnostic(severity: severity,
                                             key: key,
                                             params: params,
                                             file: fileName,
                                             line: line,
                                             api: api))
    }

    // MARK: Struct instantiation

    func instantiateStruct(_ viewStruct: PreviewViewStruct,
                             args: [(label: String?, expr: ExprSyntax)],
                             callerEnv: Env) throws -> PreviewViewNode {
        depth += 1
        defer { depth -= 1 }
        guard depth < 40 else {
            throw PreviewError(.errRecursionDeep)
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
            throw PreviewError(.errNoBody, viewStruct.name)
        }
        // §七: external dependencies need Mock data to preview.
        for req in viewStruct.mockRequirements {
            if mockStore?.value(for: req.propertyName) == nil {
                diagnose(.error, .diagMockNeeded, params: [req.propertyName])
            }
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
                    diagnose(.warning, .diagDeclInBody, params: [snippet(decl)], node: decl)
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
                } else if let returnStmt = stmt.as(ReturnStmtSyntax.self),
                          let expression = returnStmt.expression {
                    out += try viewNodes(from: expression, env: env)
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
            diagnose(.warning, .diagExprNotView, params: [snippet(expr)], node: expr)
            return []
        }
    }

    private func evalIf(_ ifExpr: IfExprSyntax, env: Env) throws -> [PreviewViewNode] {
        guard let firstCondition = ifExpr.conditions.first,
              case .expression(let condition) = firstCondition.condition else {
            diagnose(.warning, .diagIfLet, node: ifExpr)
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
            return try evalReference(reference.baseName.text, env: env)
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
        diagnose(.warning, .diagExprUnsupported, params: [snippet(expr)], node: expr)
        return .void
    }

    private func evalReference(_ name: String, env: Env) throws -> PreviewValue {
        if name.hasPrefix("$") {
            let property = String(name.dropFirst())
            if let key = env.stateKeys[property] { return .binding(key) }
            diagnose(.warning, .diagNotState, params: [property])
            return .void
        }
        if let local = env.locals[name] { return local }
        if let key = env.stateKeys[name] { return runtime.value(key) ?? .void }
        if let computed = activeViews[env.typeName]?.computedViews[name] {
            return try invokeComputedView(computed, env: env)
        }
        // §六 Design token fallback: `let brand = Color(...)` / `V32.gap`.
        if let token = projectIndex?.tokensByName[name] { return token.value }
        // §七 Mock fallback before giving up.
        if let mock = mockStore?.value(for: name) { return mock }
        // 4.0.2 P0-3: a bare reference to a known cross-file type (e.g.
        // `DemoMode`) stubs instead of erroring — never executes real code.
        if let typeInfo = activeTypes[name] {
            diagnose(.info, .diagTypePreviewDefault, params: [name], api: name, node: nil)
            return .typeStub(typeInfo.name)
        }
        diagnose(.error, .diagUnknownIdentifier, params: [name], api: name, node: nil)
        return .void
    }

    /// Evaluates a `var xxx: some View { ... }` computed subview in the
    /// current env, so @State and locals stay visible. Depth-guarded against
    /// mutually recursive computed views.
    private func invokeComputedView(_ computed: PreviewComputedView, env: Env) throws -> PreviewValue {
        depth += 1
        defer { depth -= 1 }
        guard depth < 40 else {
            throw PreviewError(.errRecursionDeep)
        }
        guard let statements = computed.bodyStatements else { return .void }
        let children = try viewBuilderChildren(statements, env: env)
        if children.count == 1 { return .view(children[0]) }
        if children.isEmpty { return .void }
        return .view(PreviewViewNode(kind: .group(children)))
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
            // §六/§七 qualified lookup: `V32Layout.sectionGap` may be a design
            // token or a mock value when the base type is otherwise unknown.
            let qualified = "\(reference.baseName.text).\(name)"
            // 4.0.2 P0-3: cross-file ordinary types — `DemoMode.shared`,
            // `DemoCatalog.monthlyRevenue`. Static lets with literal values
            // resolve directly; opaque statics (e.g. `shared = DemoMode()`,
            // anything with side effects) become type stubs. Never executed.
            if let typeInfo = activeTypes[reference.baseName.text] {
                if let value = typeInfo.staticValues[name] { return value }
                if typeInfo.opaqueStatics.contains(name) {
                    // Enum cases behave like unqualified members (`.demo`).
                    if typeInfo.kind == .enum { return .member(name) }
                    return .typeStub(typeInfo.name)
                }
            }
            if let token = projectIndex?.tokensByName[qualified] { return token.value }
            if let mock = mockStore?.value(for: qualified) { return mock }
        }

        let baseValue = try eval(base, env: env)
        switch (baseValue, name) {
        case (.string(let s), "count"): return .number(Double(s.count))
        case (.string(let s), "isEmpty"): return .bool(s.isEmpty)
        case (.array(let a), "count"): return .number(Double(a.count))
        case (.array(let a), "isEmpty"): return .bool(a.isEmpty)
        case (.color(let c), "gradient"): return .color(c)   // close enough for a preview
        case (.member, _): return .member(name)
        case (.typeStub(let typeName), _):
            // 4.0.2 P0-3: `DemoMode.shared.isEnabled` — resolve the declared
            // type annotation to a preview default; never runs `didSet`.
            if let declared = activeTypes[typeName]?.instanceMembers[name] {
                diagnose(.info, .diagTypePreviewDefault,
                         params: ["\(typeName).\(name)"], api: name, node: member)
                return Self.previewDefault(forTypeName: declared)
            }
            diagnose(.warning, .diagMemberUnsupported, params: [name], api: name, node: member)
            return .void
        default:
            diagnose(.warning, .diagMemberUnsupported, params: [name], api: name, node: member)
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
            diagnose(.warning, .diagOperatorUnsupported, params: [op], api: op, node: infix)
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
                diagnose(.warning, .diagActionUnsupported, params: [snippet(expr)], node: expr)
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

        diagnose(.warning, .diagActionUnsupported, params: [snippet(expr)], node: expr)
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
        "primary": .primary, "secondary": .secondary, "accentColor": .accentColor,
        // SwiftUI has no Color.tertiary — approximate it.
        "tertiary": Color.secondary.opacity(0.55)
    ]

    static let materialTable: [String: Material] = [
        "ultraThinMaterial": .ultraThinMaterial,
        "thinMaterial": .thinMaterial,
        "regularMaterial": .regularMaterial
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
