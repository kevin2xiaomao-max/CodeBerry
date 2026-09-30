import SwiftUI

// MARK: - Renderable model produced by the evaluator

enum PreviewStackAxis { case vertical, horizontal, depth }

enum PreviewShapeKind {
    case circle, rectangle, roundedRectangle(Double), capsule, ellipse
}

enum PreviewModifierOp {
    case padding(Edge.Set, Double?)
    case font(Font)
    case fontWeight(Font.Weight)
    case bold
    case italic
    case foreground(Color)
    case background(Color)
    case backgroundShape(Color, PreviewShapeKind)
    case backgroundMaterial(Material, PreviewShapeKind?)
    case overlay([PreviewViewNode])
    case tint(Color)
    case frame(w: Double?, h: Double?, minW: Double?, minH: Double?,
               maxW: Double?, maxH: Double?, alignment: String?)
    case cornerRadius(Double)
    case clip(PreviewShapeKind)
    case opacity(Double)
    case shadow(Double)
    case lineLimit(Int)
    case textAlign(TextAlignment)
    case buttonStyle(String)
    case imageScale(String)
}

/// One node of the interpreted view tree.
struct PreviewViewNode {
    indirect enum Kind {
        case text(String)
        case image(systemName: String)
        case label(title: String, systemImage: String)
        case stack(PreviewStackAxis, alignment: String?, spacing: Double?, children: [PreviewViewNode])
        case spacer
        case divider
        case button(label: [PreviewViewNode], action: (() -> Void)?)
        case toggle(title: String, key: String?, fallback: Bool)
        case textField(placeholder: String, key: String?)
        case slider(key: String?, lower: Double, upper: Double)
        case list([PreviewViewNode])
        case group([PreviewViewNode])
        case shape(PreviewShapeKind)
        case strokedShape(PreviewShapeKind, Color, Double)
        case colorView(Color)
        case progress
        case unsupported(String)
    }

    var kind: Kind
    var modifiers: [PreviewModifierOp] = []
}

// MARK: - Renderer

/// Maps an interpreted node onto real SwiftUI views.
struct PreviewNodeView: View {
    let node: PreviewViewNode
    let runtime: PreviewRuntime

    var body: some View {
        Self.applying(node.modifiers, to: AnyView(base), runtime: runtime)
    }

    @ViewBuilder
    private var base: some View {
        switch node.kind {
        case .text(let string):
            Text(string)
        case .image(let systemName):
            Image(systemName: systemName)
        case .label(let title, let systemImage):
            Label(title, systemImage: systemImage)
        case .stack(let axis, let alignment, let spacing, let children):
            stack(axis, alignment, spacing, children)
        case .spacer:
            Spacer()
        case .divider:
            Divider()
        case .button(let label, let action):
            Button(action: { action?() }) {
                if label.count == 1 {
                    PreviewNodeView(node: label[0], runtime: runtime)
                } else {
                    HStack(spacing: 6) { render(label) }
                }
            }
        case .toggle(let title, let key, let fallback):
            Toggle(title, isOn: boolBinding(key, fallback: fallback))
        case .textField(let placeholder, let key):
            TextField(placeholder, text: stringBinding(key))
                .textFieldStyle(.roundedBorder)
        case .slider(let key, let lower, let upper):
            Slider(value: doubleBinding(key, fallback: lower), in: lower...upper)
        case .list(let children):
            pseudoList(children)
        case .group(let children):
            VStack(alignment: .leading, spacing: 8) { render(children) }
        case .shape(let kind):
            Self.shapePath(kind).fill(Color.primary)
        case .strokedShape(let kind, let color, let lineWidth):
            Self.shapePath(kind).stroke(color, lineWidth: lineWidth)
        case .colorView(let color):
            color
        case .progress:
            ProgressView()
        case .unsupported(let name):
            Label(name, systemImage: "questionmark.square.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
    }

    @ViewBuilder
    private func render(_ children: [PreviewViewNode]) -> some View {
        ForEach(children.indices, id: \.self) { index in
            PreviewNodeView(node: children[index], runtime: runtime)
        }
    }

    @ViewBuilder
    private func stack(_ axis: PreviewStackAxis, _ alignment: String?,
                       _ spacing: Double?, _ children: [PreviewViewNode]) -> some View {
        let gap = spacing.map { CGFloat($0) }
        switch axis {
        case .vertical:
            VStack(alignment: Self.horizontalAlignment(alignment), spacing: gap) { render(children) }
        case .horizontal:
            HStack(alignment: Self.verticalAlignment(alignment), spacing: gap) { render(children) }
        case .depth:
            ZStack(alignment: Self.alignment(alignment)) { render(children) }
        }
    }

    /// List look-alike that behaves inside the canvas's own ScrollView.
    private func pseudoList(_ children: [PreviewViewNode]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children.indices, id: \.self) { index in
                PreviewNodeView(node: children[index], runtime: runtime)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if index < children.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Bindings into the preview runtime

    private func boolBinding(_ key: String?, fallback: Bool) -> Binding<Bool> {
        guard let key else { return .constant(fallback) }
        return Binding(get: { runtime.boolValue(key, fallback: fallback) },
                       set: { runtime.set(key, .bool($0)) })
    }

    private func stringBinding(_ key: String?) -> Binding<String> {
        guard let key else { return .constant("") }
        return Binding(get: { runtime.stringValue(key) },
                       set: { runtime.set(key, .string($0)) })
    }

    private func doubleBinding(_ key: String?, fallback: Double) -> Binding<Double> {
        guard let key else { return .constant(fallback) }
        return Binding(get: { runtime.doubleValue(key, fallback: fallback) },
                       set: { runtime.set(key, .number($0)) })
    }

    // MARK: Modifier application

    static func applying(_ ops: [PreviewModifierOp], to view: AnyView, runtime: PreviewRuntime) -> AnyView {
        var v = view
        for op in ops {
            switch op {
            case .padding(let edges, let amount):
                v = amount.map { a in AnyView(v.padding(edges, CGFloat(a))) } ?? AnyView(v.padding(edges))
            case .font(let font):
                v = AnyView(v.font(font))
            case .fontWeight(let weight):
                v = AnyView(v.fontWeight(weight))
            case .bold:
                v = AnyView(v.bold())
            case .italic:
                v = AnyView(v.italic())
            case .foreground(let color):
                v = AnyView(v.foregroundStyle(color))
            case .background(let color):
                v = AnyView(v.background(color))
            case .backgroundShape(let color, let kind):
                v = AnyView(v.background(color, in: shapePath(kind)))
            case .backgroundMaterial(let material, let kind):
                if let kind {
                    v = AnyView(v.background(material, in: shapePath(kind)))
                } else {
                    v = AnyView(v.background(material))
                }
            case .overlay(let children):
                v = AnyView(v.overlay {
                    ForEach(children.indices, id: \.self) { index in
                        PreviewNodeView(node: children[index], runtime: runtime)
                    }
                })
            case .tint(let color):
                v = AnyView(v.tint(color))
            case .frame(let w, let h, let minW, let minH, let maxW, let maxH, let alignmentName):
                let a = alignment(alignmentName)
                if w != nil || h != nil {
                    v = AnyView(v.frame(width: w.map { CGFloat($0) },
                                        height: h.map { CGFloat($0) },
                                        alignment: a))
                }
                if minW != nil || minH != nil || maxW != nil || maxH != nil {
                    v = AnyView(v.frame(minWidth: minW.map { CGFloat($0) },
                                        maxWidth: maxW.map { CGFloat($0) },
                                        minHeight: minH.map { CGFloat($0) },
                                        maxHeight: maxH.map { CGFloat($0) },
                                        alignment: a))
                }
            case .cornerRadius(let radius):
                v = AnyView(v.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
            case .clip(let kind):
                v = AnyView(v.clipShape(shapePath(kind)))
            case .opacity(let value):
                v = AnyView(v.opacity(value))
            case .shadow(let radius):
                v = AnyView(v.shadow(radius: radius))
            case .lineLimit(let limit):
                v = AnyView(v.lineLimit(limit))
            case .textAlign(let alignment):
                v = AnyView(v.multilineTextAlignment(alignment))
            case .buttonStyle(let name):
                switch name {
                case "borderedProminent": v = AnyView(v.buttonStyle(.borderedProminent))
                case "bordered": v = AnyView(v.buttonStyle(.bordered))
                case "borderless": v = AnyView(v.buttonStyle(.borderless))
                case "plain": v = AnyView(v.buttonStyle(.plain))
                default: break
                }
            case .imageScale(let name):
                switch name {
                case "small": v = AnyView(v.imageScale(.small))
                case "large": v = AnyView(v.imageScale(.large))
                default: v = AnyView(v.imageScale(.medium))
                }
            }
        }
        return v
    }

    // MARK: Lookup helpers

    static func shapePath(_ kind: PreviewShapeKind) -> AnyShape {
        switch kind {
        case .circle: AnyShape(Circle())
        case .rectangle: AnyShape(Rectangle())
        case .roundedRectangle(let radius): AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule: AnyShape(Capsule())
        case .ellipse: AnyShape(Ellipse())
        }
    }

    static func alignment(_ name: String?) -> Alignment {
        switch name {
        case "leading": .leading
        case "trailing": .trailing
        case "top": .top
        case "bottom": .bottom
        case "topLeading": .topLeading
        case "topTrailing": .topTrailing
        case "bottomLeading": .bottomLeading
        case "bottomTrailing": .bottomTrailing
        default: .center
        }
    }

    static func horizontalAlignment(_ name: String?) -> HorizontalAlignment {
        switch name {
        case "leading": .leading
        case "trailing": .trailing
        default: .center
        }
    }

    static func verticalAlignment(_ name: String?) -> VerticalAlignment {
        switch name {
        case "top": .top
        case "bottom": .bottom
        case "firstTextBaseline": .firstTextBaseline
        default: .center
        }
    }
}
