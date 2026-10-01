import SwiftUI
import SwiftSyntax

/// Function-call evaluation: SwiftUI view factories, custom view structs,
/// and view modifiers.
extension PreviewEvaluator {

    /// §三 Wrapper: every view-producing call gets source info attached, so the
    /// Inspector can tap-to-select and map overrides back to code ranges.
    func evalCall(_ call: FunctionCallExprSyntax, env: Env) throws -> PreviewValue {
        let value = try evalCallInner(call, env: env)
        if case .view(var node) = value, node.source == nil,
           let info = sourceInfo(for: ExprSyntax(call)) {
            node.source = info
            return .view(node)
        }
        return value
    }

    private func evalCallInner(_ call: FunctionCallExprSyntax, env: Env) throws -> PreviewValue {
        let args = call.arguments.map { (label: $0.label?.text, expr: $0.expression) }

        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return try evalFactory(named: reference.baseName.text, call: call, args: args, env: env)
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            guard let base = member.base else {
                // Bare-member call like `.system(size: 17)` — let contexts
                // (fontValue etc.) handle these; standalone it's unsupported.
                diagnose(.warning, .diagCallUnsupported, params: [name], api: name, node: member)
                return .void
            }
            if let baseRef = base.as(DeclReferenceExprSyntax.self), baseRef.baseName.text == "Font" {
                return .font(fontValue(from: ExprSyntax(call), env: env) ?? .body)
            }
            let baseValue = try eval(base, env: env)
            if case .view(var node) = baseValue {
                try applyModifier(named: name, call: call, args: args, to: &node, env: env)
                return .view(node)
            }
            if name == "opacity", let amount = try numberArg(args.first?.expr, env: env) {
                switch baseValue {
                case .color(let color):
                    return .color(color.opacity(amount))
                case .member(let m):
                    // Bare-member color chain like `.white.opacity(0.75)`.
                    if let color = Self.colorTable[m] {
                        return .color(color.opacity(amount))
                    }
                default:
                    break
                }
            }
            if case .color(let color) = baseValue, Self.cosmeticModifiers.contains(name) {
                // e.g. `page.ignoresSafeArea()` on a Color value — drop the
                // modifier silently and keep the color so it still renders.
                return .color(color)
            }
            if case .string(let string) = baseValue {
                switch name {
                case "uppercased": return .string(string.uppercased())
                case "lowercased": return .string(string.lowercased())
                default: break
                }
            }
            diagnose(.warning, .diagMethodUnsupported, params: [name], api: name, node: call)
            return .void
        }
        diagnose(.warning, .diagCallUnsupported, params: [call.calledExpression.trimmedDescription], node: call)
        return .void
    }

    // MARK: View factories

    private func evalFactory(named name: String, call: FunctionCallExprSyntax,
                             args: [(label: String?, expr: ExprSyntax)],
                             env: Env) throws -> PreviewValue {
        switch name {
        case "Text":
            let value = try args.first.map { try eval($0.expr, env: env) } ?? .string("")
            return .view(PreviewViewNode(kind: .text(value.display)))

        case "Image":
            if let systemName = args.first(where: { $0.label == "systemName" }) {
                let value = try eval(systemName.expr, env: env)
                return .view(PreviewViewNode(kind: .image(systemName: value.display)))
            }
            return .view(PreviewViewNode(kind: .unsupported("Image(asset)")))

        case "Label":
            let title = try args.first(where: { $0.label == nil }).map { try eval($0.expr, env: env) }?.display ?? ""
            let symbol = try args.first(where: { $0.label == "systemImage" }).map { try eval($0.expr, env: env) }?.display ?? "circle"
            return .view(PreviewViewNode(kind: .label(title: title, systemImage: symbol)))

        case "VStack", "LazyVStack":
            return .view(try stackNode(.vertical, call: call, args: args, env: env))
        case "HStack", "LazyHStack":
            return .view(try stackNode(.horizontal, call: call, args: args, env: env))
        case "ZStack":
            return .view(try stackNode(.depth, call: call, args: args, env: env))

        case "Spacer":
            return .view(PreviewViewNode(kind: .spacer))
        case "Divider":
            return .view(PreviewViewNode(kind: .divider))

        case "Group", "NavigationStack", "NavigationView", "ScrollView", "Section":
            return .view(PreviewViewNode(kind: .group(try builderChildren(call, env: env))))

        case "List":
            return .view(PreviewViewNode(kind: .list(try builderChildren(call, env: env))))

        case "Button":
            return .view(try buttonNode(call: call, args: args, env: env))

        case "Toggle":
            let title = try args.first(where: { $0.label == nil }).map { try eval($0.expr, env: env) }?.display ?? ""
            let binding = try args.first(where: { $0.label == "isOn" }).map { try eval($0.expr, env: env) }
            if case .binding(let key) = binding {
                return .view(PreviewViewNode(kind: .toggle(title: title, key: key,
                                                           fallback: runtime.boolValue(key))))
            }
            return .view(PreviewViewNode(kind: .toggle(title: title, key: nil,
                                                       fallback: binding?.boolValue ?? false)))

        case "TextField":
            let placeholder = try args.first(where: { $0.label == nil }).map { try eval($0.expr, env: env) }?.display ?? ""
            let binding = try args.first(where: { $0.label == "text" }).map { try eval($0.expr, env: env) }
            if case .binding(let key) = binding {
                return .view(PreviewViewNode(kind: .textField(placeholder: placeholder, key: key)))
            }
            return .view(PreviewViewNode(kind: .textField(placeholder: placeholder, key: nil)))

        case "Slider":
            let binding = try args.first(where: { $0.label == "value" }).map { try eval($0.expr, env: env) }
            var lower = 0.0, upper = 1.0
            if let rangeArg = args.first(where: { $0.label == "in" }),
               case .range(let lo, let hi, _) = try eval(rangeArg.expr, env: env) {
                lower = Double(lo); upper = Double(hi)
            }
            if case .binding(let key) = binding {
                return .view(PreviewViewNode(kind: .slider(key: key, lower: lower, upper: upper)))
            }
            return .view(PreviewViewNode(kind: .slider(key: nil, lower: lower, upper: upper)))

        case "ForEach":
            return .view(try forEachNode(call: call, args: args, env: env))

        case "Circle": return .view(PreviewViewNode(kind: .shape(.circle)))
        case "Rectangle": return .view(PreviewViewNode(kind: .shape(.rectangle)))
        case "RoundedRectangle":
            let radius = try numberArg(args.first(where: { $0.label == "cornerRadius" })?.expr, env: env) ?? 8
            return .view(PreviewViewNode(kind: .shape(.roundedRectangle(radius))))
        case "Capsule": return .view(PreviewViewNode(kind: .shape(.capsule)))
        case "Ellipse": return .view(PreviewViewNode(kind: .shape(.ellipse)))

        case "ProgressView":
            return .view(PreviewViewNode(kind: .progress))

        case "Color":
            let red = try numberArg(args.first(where: { $0.label == "red" })?.expr, env: env)
            let green = try numberArg(args.first(where: { $0.label == "green" })?.expr, env: env)
            let blue = try numberArg(args.first(where: { $0.label == "blue" })?.expr, env: env)
            if let red, let green, let blue {
                let opacity = try numberArg(args.first(where: { $0.label == "opacity" })?.expr, env: env) ?? 1
                return .color(Color(red: red, green: green, blue: blue, opacity: opacity))
            }
            return .color(.gray)

        case "Int", "Double", "CGFloat", "Float":
            let value = try args.first.map { try eval($0.expr, env: env) } ?? .number(0)
            if case .string(let s) = value { return .number(Double(s) ?? 0) }
            return .number(value.doubleValue ?? 0)

        // MARK: - 4.0.2 P0-5: approximated SwiftUI containers.
        // Approximate rather than unsupported wherever a visual reading
        // is possible — these used to render as [?].

        case "TabView":
            // No tab switching in preview — render all pages.
            return .view(PreviewViewNode(kind: .group(try builderChildren(call, env: env))))

        case "ToolbarItem", "WindowGroup":
            // Toolbar chrome is dropped (cosmetic); WindowGroup is an App
            // scene container — render the content inline in both cases.
            return .view(PreviewViewNode(kind: .group(try builderChildren(call, env: env))))

        case "ContentUnavailableView":
            var cuChildren: [PreviewViewNode] = []
            if let titleExpr = args.first(where: { $0.label == nil })?.expr,
               let title = try? eval(titleExpr, env: env), !title.display.isEmpty {
                cuChildren.append(PreviewViewNode(kind: .text(title.display)))
            }
            cuChildren += try builderChildren(call, env: env)
            if cuChildren.isEmpty {
                cuChildren.append(PreviewViewNode(kind: .text("ContentUnavailableView")))
            }
            return .view(PreviewViewNode(kind: .group(cuChildren)))

        case "GroupBox":
            var gbChildren: [PreviewViewNode] = []
            if let titleExpr = args.first(where: { $0.label == nil })?.expr,
               let title = try? eval(titleExpr, env: env), !title.display.isEmpty {
                gbChildren.append(PreviewViewNode(kind: .text(title.display)))
            }
            if let labelExpr = args.first(where: { $0.label == "label" })?.expr {
                gbChildren += try closureChildren(labelExpr, env: env)
            }
            gbChildren += try builderChildren(call, env: env)
            return .view(PreviewViewNode(kind: .group(gbChildren)))

        case "NavigationLink":
            // The destination is navigation, not preview content —
            // render the label only.
            var linkChildren: [PreviewViewNode] = []
            if let first = args.first(where: { $0.label == nil }) {
                if let closure = first.expr.as(ClosureExprSyntax.self) {
                    linkChildren += try viewBuilderChildren(closure.statements, env: env)
                } else if let label = try? eval(first.expr, env: env),
                          !label.display.isEmpty {
                    linkChildren.append(PreviewViewNode(kind: .text(label.display)))
                }
            }
            linkChildren += try builderChildren(call, env: env)
            return .view(PreviewViewNode(kind: .group(linkChildren)))

        case "LazyVGrid":
            return .view(try stackNode(.vertical, call: call, args: args, env: env))

        case "LazyHGrid":
            return .view(try stackNode(.horizontal, call: call, args: args, env: env))

        case "GridItem":
            // Layout metadata, not visual — renders nothing, no warning.
            return .void

        case "AnyView":
            if let first = args.first,
               case .view(let node) = try eval(first.expr, env: env) {
                return .view(node)
            }
            return .void

        case "EmptyView":
            return .void

        case "GeometryReader", "ScrollViewReader":
            return .view(PreviewViewNode(kind: .group(
                try readerChildren(call: call, env: env))))

        case "Form":
            return .view(PreviewViewNode(kind: .list(try builderChildren(call, env: env))))

        case "Link":
            let linkTitle = try args.first(where: { $0.label == nil })
                .map { try eval($0.expr, env: env) }?.display ?? ""
            return .view(PreviewViewNode(kind: .text(
                linkTitle.isEmpty ? "Link" : linkTitle)))

        default:
            // 4.0.2 P0-2: cross-file component resolution order —
            //   1. current file (`doc`, wins via `activeViews` merge),
            //   2. project index (`PreviewProjectIndex`, unified 1000-file cap),
            //   3. registered custom components (`ViewRegistry`),
            //   4. `.unsupported` placeholder (never a throw, never silent).
            if let function = activeViews[env.typeName]?.functions[name] {
                return try invokeFunction(function, args: args, env: env)
            }
            if let viewStruct = activeViews[name] {
                return .view(try instantiate(name: name, viewStruct: viewStruct, args: args, env: env))
            }
            // M3 §15: registry hook — custom views render without editing
            // the evaluator core. Only additive; falls through to the
            // unsupported placeholder when nothing is registered.
            if let custom = try ViewRegistry.evaluateCustom(named: name, args: args,
                                                            evaluator: self, env: env) {
                return custom
            }
            // 4.0.2 P1-8: external packages are never executed. They get an
            // explicit "not executed" placeholder (not the generic [?]),
            // and never block the rest of the page. Project-defined views
            // with the same name already won above, so this can't shadow
            // user code.
            if let package = Self.externalPackages[name] {
                diagnose(.warning, .diagExternalPackageNotExecuted,
                         params: [name, package], api: name, node: call)
                return .view(PreviewViewNode(kind: .externalPackage(package: package,
                                                                   symbol: name)))
            }
            diagnose(.warning, .diagFactoryUnsupported, params: [name], api: name, node: call)
            return .view(PreviewViewNode(kind: .unsupported(name)))
        }
    }

    // MARK: - 4.0.2 P1-8: external packages

    /// External-package symbols mapped to their package. These are never
    /// executed — the evaluator renders an explicit placeholder instead.
    /// (Checked after current-file/index/registry so user-defined views
    /// with colliding names still win.)
    private static let externalPackages: [String: String] = [
        // Charts
        "Chart": "Charts", "BarMark": "Charts", "LineMark": "Charts",
        "PointMark": "Charts", "AreaMark": "Charts",
        "RectangleMark": "Charts", "RuleMark": "Charts",
        // MapKit
        "Map": "MapKit", "MapMarker": "MapKit", "MapAnnotation": "MapKit",
        "MapCircle": "MapKit", "MapPolygon": "MapKit", "MapPolyline": "MapKit",
        // AVKit
        "VideoPlayer": "AVKit",
        // WebKit (common wrapper name)
        "WebView": "WebKit",
    ]

    /// Calls a `func xxx(...) -> some View` helper defined in the current view
    /// struct. Arguments bind to parameters by external label first, then by
    /// position for `_ name:` (unlabeled) parameters. The child env inherits
    /// the caller's locals and @State.
    private func invokeFunction(_ function: PreviewFunction,
                                args: [(label: String?, expr: ExprSyntax)],
                                env: Env) throws -> PreviewValue {
        depth += 1
        defer { depth -= 1 }
        guard depth < 40 else {
            throw PreviewError(.errRecursionDeep)
        }
        var childEnv = env
        var consumed = Set<Int>()
        for param in function.parameters {
            if let label = param.externalLabel,
               let index = args.indices.first(where: { args[$0].label == label }) {
                childEnv.locals[param.localName] = try eval(args[index].expr, env: env)
                consumed.insert(index)
            }
        }
        var remaining = args.indices.filter { !consumed.contains($0) }
        for param in function.parameters
            where param.externalLabel == nil && childEnv.locals[param.localName] == nil {
            guard !remaining.isEmpty else { break }
            let index = remaining.removeFirst()
            childEnv.locals[param.localName] = try eval(args[index].expr, env: env)
        }
        guard let statements = function.bodyStatements else { return .void }
        let children = try viewBuilderChildren(statements, env: childEnv)
        if children.count == 1 { return .view(children[0]) }
        if children.isEmpty { return .void }
        return .view(PreviewViewNode(kind: .group(children)))
    }

    private func instantiate(name: String, viewStruct: PreviewViewStruct,
                             args: [(label: String?, expr: ExprSyntax)],
                             env: Env) throws -> PreviewViewNode {
        // Re-enter the main instantiation path defined in PreviewEvaluator.
        try instantiateStruct(viewStruct, args: args, callerEnv: env)
    }

    private func stackNode(_ axis: PreviewStackAxis, call: FunctionCallExprSyntax,
                           args: [(label: String?, expr: ExprSyntax)],
                           env: Env) throws -> PreviewViewNode {
        let alignment = memberName(args.first(where: { $0.label == "alignment" })?.expr)
        let spacing = try numberArg(args.first(where: { $0.label == "spacing" })?.expr, env: env)
        return PreviewViewNode(kind: .stack(axis, alignment: alignment, spacing: spacing,
                                            children: try builderChildren(call, env: env)))
    }

    private func buttonNode(call: FunctionCallExprSyntax,
                            args: [(label: String?, expr: ExprSyntax)],
                            env: Env) throws -> PreviewViewNode {
        var label: [PreviewViewNode] = []
        var action: (() -> Void)?

        if let title = args.first(where: { $0.label == nil }),
           !title.expr.is(ClosureExprSyntax.self) {
            label = [PreviewViewNode(kind: .text((try eval(title.expr, env: env)).display))]
        }
        if let actionArg = args.first(where: { $0.label == "action" }),
           let closure = actionArg.expr.as(ClosureExprSyntax.self) {
            action = makeAction(closure, env: env)
        }

        let labelClosure = call.additionalTrailingClosures.first { $0.label.text == "label" }?.closure
        if let labelClosure {
            // Button { action } label: { views }
            label = try viewBuilderChildren(labelClosure.statements, env: env)
            if action == nil, let trailing = call.trailingClosure {
                action = makeAction(trailing, env: env)
            }
        } else if let trailing = call.trailingClosure {
            if label.isEmpty && action != nil {
                // Button(action: …) { label }
                label = try viewBuilderChildren(trailing.statements, env: env)
            } else if action == nil {
                // Button("Title") { action }
                action = makeAction(trailing, env: env)
            }
        }

        if label.isEmpty { label = [PreviewViewNode(kind: .text("Button"))] }
        return PreviewViewNode(kind: .button(label: label, action: action))
    }

    private func forEachNode(call: FunctionCallExprSyntax,
                             args: [(label: String?, expr: ExprSyntax)],
                             env: Env) throws -> PreviewViewNode {
        guard let dataArg = args.first(where: { $0.label == nil }),
              let closure = call.trailingClosure else {
            diagnose(.warning, .diagForEachNeedsClosure, node: call)
            return PreviewViewNode(kind: .unsupported("ForEach"))
        }
        let data = try eval(dataArg.expr, env: env)
        let elements: [PreviewValue]
        switch data {
        case .range(let lo, let hi, let inclusive):
            let upper = inclusive ? hi : hi - 1
            guard lo <= upper else { return PreviewViewNode(kind: .group([])) }
            elements = (lo...upper).prefix(200).map { .number(Double($0)) }
        case .array(let items):
            elements = Array(items.prefix(200))
        default:
            diagnose(.warning, .diagForEachData, node: call)
            return PreviewViewNode(kind: .unsupported("ForEach"))
        }

        let parameter = closureParameterName(closure) ?? "$0"
        var children: [PreviewViewNode] = []
        for element in elements {
            var childEnv = env
            childEnv.locals[parameter] = element
            children += try viewBuilderChildren(closure.statements, env: childEnv)
        }
        return PreviewViewNode(kind: .group(children))
    }

    private func closureParameterName(_ closure: ClosureExprSyntax) -> String? {
        switch closure.signature?.parameterClause {
        case .simpleInput(let parameters):
            return parameters.first?.name.text
        case .parameterClause(let clause):
            return clause.parameters.first?.firstName.text
        case nil:
            return nil
        }
    }

    private func builderChildren(_ call: FunctionCallExprSyntax, env: Env) throws -> [PreviewViewNode] {
        guard let trailing = call.trailingClosure else { return [] }
        return try viewBuilderChildren(trailing.statements, env: env)
    }

    /// 4.0.2 P0-5: evaluates a labeled closure argument's body
    /// (`label:` / `destination:` style, e.g. GroupBox's label).
    private func closureChildren(_ expr: ExprSyntax, env: Env) throws -> [PreviewViewNode] {
        guard let closure = expr.as(ClosureExprSyntax.self) else { return [] }
        return try viewBuilderChildren(closure.statements, env: env)
    }

    /// 4.0.2 P0-5: `GeometryReader { geo in ... }` /
    /// `ScrollViewReader { proxy in ... }` — binds the closure parameter to
    /// `.void` so references to it don't raise unknown-identifier errors,
    /// then renders the body (geometry/proxy values are approximate).
    private func readerChildren(call: FunctionCallExprSyntax, env: Env) throws -> [PreviewViewNode] {
        guard let trailing = call.trailingClosure else { return [] }
        var childEnv = env
        if let param = closureParameterName(trailing) {
            childEnv.locals[param] = .void
        }
        return try viewBuilderChildren(trailing.statements, env: childEnv)
    }

    // MARK: Modifiers

    /// Modifiers that only affect chrome/behavior the canvas can't show —
    /// dropped without a warning so diagnostics stay focused.
    private static let cosmeticModifiers: Set<String> = [
        "navigationTitle", "navigationBarTitleDisplayMode", "toolbar",
        "onAppear", "onDisappear", "onChange", "onTapGesture", "onSubmit",
        "animation", "transition", "textSelection", "listStyle",
        "scrollIndicators", "ignoresSafeArea", "resizable", "scaledToFit",
        "scaledToFill", "aspectRatio", "symbolRenderingMode", "task",
        "accessibilityLabel", "accessibilityHint", "id", "tag", "disabled",
        "contentShape", "interactiveDismissDisabled", "fontDesign", "kerning",
        "minimumScaleFactor"
    ]

    private func applyModifier(named name: String, call: FunctionCallExprSyntax,
                               args: [(label: String?, expr: ExprSyntax)],
                               to node: inout PreviewViewNode, env: Env) throws {
        switch name {
        // 4.0.2 P0-5: safeAreaPadding behaves like padding on the canvas.
        case "padding", "safeAreaPadding":
            var edges: Edge.Set = .all
            var amount: Double?
            for arg in args {
                if let member = memberName(arg.expr) {
                    edges = Self.edgeSet(member)
                } else if let number = try numberArg(arg.expr, env: env) {
                    amount = number
                }
            }
            node.modifiers.append(.padding(edges, amount))
        case "font":
            node.modifiers.append(.font(fontValue(from: args.first?.expr, env: env) ?? .body))
        case "fontWeight":
            if let member = memberName(args.first?.expr), let weight = Self.weightTable[member] {
                node.modifiers.append(.fontWeight(weight))
            }
        case "bold":
            node.modifiers.append(.bold)
        case "italic":
            node.modifiers.append(.italic)
        case "foregroundStyle", "foregroundColor":
            if let color = try colorValue(from: args.first?.expr, env: env) {
                node.modifiers.append(.foreground(color))
            }
        case "tint":
            if let color = try colorValue(from: args.first?.expr, env: env) {
                node.modifiers.append(.tint(color))
            }
        case "background":
            let firstExpr = args.first(where: { $0.label == nil })?.expr
            let inShape = try shapeKind(from: args.first(where: { $0.label == "in" })?.expr, env: env)
            if let firstExpr, let member = memberName(firstExpr),
               let material = Self.materialTable[member] {
                node.modifiers.append(.backgroundMaterial(material, inShape))
            } else if let color = try colorValue(from: firstExpr, env: env) {
                if let shape = inShape {
                    node.modifiers.append(.backgroundShape(color, shape))
                } else {
                    node.modifiers.append(.background(color))
                }
            } else if let firstExpr,
                      case .view(let shapeNode) = try eval(firstExpr, env: env),
                      let (kind, color) = Self.filledShape(of: shapeNode) {
                // `.background(RoundedRectangle(...).fill(color))`: the fill
                // is recorded as `.foreground` on the shape node.
                node.modifiers.append(.backgroundShape(color, kind))
            }
        case "overlay":
            var children: [PreviewViewNode] = []
            if let trailing = call.trailingClosure {
                children = try viewBuilderChildren(trailing.statements, env: env)
            } else if let first = args.first?.expr {
                switch try eval(first, env: env) {
                case .view(let child): children = [child]
                case .color(let color): children = [PreviewViewNode(kind: .colorView(color))]
                default: break
                }
            }
            node.modifiers.append(.overlay(children))
        case "frame":
            var w: Double?, h: Double?, minW: Double?, minH: Double?
            var maxW: Double?, maxH: Double?
            var alignment: String?
            for arg in args {
                switch arg.label {
                case "width": w = try numberArg(arg.expr, env: env)
                case "height": h = try numberArg(arg.expr, env: env)
                case "minWidth": minW = try numberArg(arg.expr, env: env)
                case "minHeight": minH = try numberArg(arg.expr, env: env)
                case "maxWidth": maxW = try numberArg(arg.expr, env: env)
                case "maxHeight": maxH = try numberArg(arg.expr, env: env)
                case "alignment": alignment = memberName(arg.expr)
                default: break
                }
            }
            node.modifiers.append(.frame(w: w, h: h, minW: minW, minH: minH,
                                         maxW: maxW, maxH: maxH, alignment: alignment))
        case "cornerRadius":
            node.modifiers.append(.cornerRadius(try numberArg(args.first?.expr, env: env) ?? 8))
        case "clipShape":
            if let shape = try shapeKind(from: args.first?.expr, env: env) {
                node.modifiers.append(.clip(shape))
            }
        case "opacity":
            node.modifiers.append(.opacity(try numberArg(args.first?.expr, env: env) ?? 1))
        case "shadow":
            let radius = try numberArg(args.first(where: { $0.label == "radius" })?.expr, env: env) ?? 4
            node.modifiers.append(.shadow(radius))
        case "lineLimit":
            node.modifiers.append(.lineLimit(Int(try numberArg(args.first?.expr, env: env) ?? 1)))
        case "multilineTextAlignment":
            switch memberName(args.first?.expr) {
            case "leading": node.modifiers.append(.textAlign(.leading))
            case "trailing": node.modifiers.append(.textAlign(.trailing))
            default: node.modifiers.append(.textAlign(.center))
            }
        case "buttonStyle":
            node.modifiers.append(.buttonStyle(memberName(args.first?.expr) ?? "automatic"))
        case "imageScale":
            node.modifiers.append(.imageScale(memberName(args.first?.expr) ?? "medium"))
        case "fill":
            if let color = try colorValue(from: args.first?.expr, env: env) {
                node.modifiers.append(.foreground(color))
            }
        case "stroke", "strokeBorder":
            if case .shape(let kind) = node.kind {
                let color = (try colorValue(from: args.first(where: { $0.label == nil })?.expr, env: env)) ?? .primary
                let width = try numberArg(args.first(where: { $0.label == "lineWidth" })?.expr, env: env) ?? 1
                node.kind = .strokedShape(kind, color, width)
            }
        default:
            if !Self.cosmeticModifiers.contains(name) {
                diagnose(.ignored, .diagModifierIgnored, params: [name], api: name, node: call)
            }
        }
    }

    // MARK: Contextual argument helpers

    func numberArg(_ expr: ExprSyntax?, env: Env) throws -> Double? {
        guard let expr else { return nil }
        if let member = memberName(expr), member == "infinity" { return .infinity }
        return (try eval(expr, env: env)).doubleValue
    }

    /// Bare `.foo` member name, e.g. `.leading`, `.title`, `.infinity`.
    func memberName(_ expr: ExprSyntax?) -> String? {
        guard let member = expr?.as(MemberAccessExprSyntax.self), member.base == nil else { return nil }
        return member.declName.baseName.text
    }

    /// A shape node carrying a fill color (`.fill(...)` is recorded as
    /// `.foreground` on the shape) — for `.background(Shape().fill(color))`.
    static func filledShape(of node: PreviewViewNode) -> (PreviewShapeKind, Color)? {
        guard case .shape(let kind) = node.kind else { return nil }
        for mod in node.modifiers {
            if case .foreground(let color) = mod { return (kind, color) }
        }
        return nil
    }

    func colorValue(from expr: ExprSyntax?, env: Env) throws -> Color? {
        guard let expr else { return nil }
        if let member = memberName(expr) { return Self.colorTable[member] }
        let value = try eval(expr, env: env)
        if case .color(let color) = value { return color }
        // Ternaries and member chains can surface a bare `.white`-style
        // member instead of a resolved color.
        if case .member(let m) = value { return Self.colorTable[m] }
        return nil
    }

    func fontValue(from expr: ExprSyntax?, env: Env) -> Font? {
        guard let expr else { return nil }
        if let member = memberName(expr) { return Self.fontTable[member] }
        // Chained styling like `.title.bold()` / `.headline.weight(.heavy)`.
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let baseFont = fontValue(from: member.base, env: env) {
            switch member.declName.baseName.text {
            case "bold": return baseFont.bold()
            case "italic": return baseFont.italic()
            case "monospaced": return baseFont.monospaced()
            case "weight":
                let weight = memberName(call.arguments.first?.expression)
                    .flatMap { Self.weightTable[$0] } ?? .regular
                return baseFont.weight(weight)
            default: return baseFont
            }
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "system" {
            let args = call.arguments.map { (label: $0.label?.text, expr: $0.expression) }
            let size = (try? numberArg(args.first(where: { $0.label == "size" })?.expr, env: env)) ?? 17
            let weight = memberName(args.first(where: { $0.label == "weight" })?.expr)
                .flatMap { Self.weightTable[$0] } ?? .regular
            let design: Font.Design = switch memberName(args.first(where: { $0.label == "design" })?.expr) {
            case "monospaced": .monospaced
            case "rounded": .rounded
            case "serif": .serif
            default: .default
            }
            return .system(size: size ?? 17, weight: weight, design: design)
        }
        if let value = try? eval(expr, env: env), case .font(let font) = value { return font }
        return nil
    }

    func shapeKind(from expr: ExprSyntax?, env: Env) throws -> PreviewShapeKind? {
        guard let call = expr?.as(FunctionCallExprSyntax.self),
              let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else { return nil }
        switch reference.baseName.text {
        case "Circle": return .circle
        case "Rectangle": return .rectangle
        case "Capsule": return .capsule
        case "Ellipse": return .ellipse
        case "RoundedRectangle":
            let args = call.arguments.map { (label: $0.label?.text, expr: $0.expression) }
            let radius = try numberArg(args.first(where: { $0.label == "cornerRadius" })?.expr, env: env) ?? 8
            return .roundedRectangle(radius)
        default: return nil
        }
    }

    static func edgeSet(_ name: String) -> Edge.Set {
        switch name {
        case "horizontal": .horizontal
        case "vertical": .vertical
        case "top": .top
        case "bottom": .bottom
        case "leading": .leading
        case "trailing": .trailing
        default: .all
        }
    }
}
