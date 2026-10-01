import Foundation
import SwiftSyntax

// MARK: - M3 §15 Component Registry
//
// Split into four registries: View / Modifier / Shape / Style.
// Each entry carries: symbol, accepted args, evaluator, renderer,
// diagnostics, support level.
//
// The point of the split (§15): adding a future component
// (LazyVStack, Grid, Menu, Picker, Gauge, …) must NOT require touching
// the evaluator core. Views get a real hook — the evaluator's
// `evalFactory` default case consults `ViewRegistry.evaluateCustom`
// before emitting an "unsupported" node. Modifiers/Shapes/Styles are
// metadata today with a registration API; their renderer hooks land
// where the core already dispatches them (documented per registry).

/// How well the Lite evaluator handles a component (§24 dashboard levels).
enum ComponentSupportLevel: String, Sendable, Hashable, CaseIterable {
    case supported       // ✅ full fidelity
    case approximate     // 🟡 close visual approximation
    case cosmeticIgnore  // silently ignored, no visual effect
    case unsupported     // 🔴 renders as an "unsupported" placeholder
}

enum ComponentKind: String, Sendable {
    case view, modifier, shape, style
}

/// One registry entry: symbol + accepted args + evaluator + renderer +
/// diagnostics + support level (§15).
struct ComponentEntry: Hashable, Sendable {
    let symbol: String
    let kind: ComponentKind
    let acceptedArgs: [String]
    let supportLevel: ComponentSupportLevel
    /// 中文说明 shown in the dashboard / inspector.
    let diagnostics: String
    let workaround: String?
}

// MARK: - View registry

/// Handler for a registered custom view. Receives the evaluator so it can
/// reuse `eval` for its arguments — same power as a built-in factory case,
/// without editing `PreviewEvaluator+Calls.swift`.
typealias CustomViewHandler = @Sendable (PreviewEvaluator, String,
    [(label: String?, expr: ExprSyntax)], PreviewEvaluator.Env) throws -> PreviewValue?

enum ViewRegistry {
    // All access is serialized through `lock`; in practice everything runs
    // on the main thread (evaluator is driven by @MainActor view code).
    private final class Storage: @unchecked Sendable {
        var handlers: [String: CustomViewHandler] = [:]
        var entries: [String: ComponentEntry] = [:]
    }
    private static let storage = Storage()
    private static let lock = NSLock()

    /// §15: register a new view without modifying the evaluator core.
    static func register(symbol: String, acceptedArgs: [String] = [],
                        supportLevel: ComponentSupportLevel = .supported,
                        diagnostics: String = "",
                        handler: @escaping CustomViewHandler) {
        lock.withLock {
            storage.handlers[symbol] = handler
            storage.entries[symbol] = ComponentEntry(symbol: symbol, kind: .view,
                acceptedArgs: acceptedArgs, supportLevel: supportLevel,
                diagnostics: diagnostics, workaround: nil)
        }
    }

    /// Called from the evaluator's factory default case (the ONLY core
    /// touch-point; additive, before the unsupported fallback).
    static func evaluateCustom(named name: String,
                               args: [(label: String?, expr: ExprSyntax)],
                               evaluator: PreviewEvaluator,
                               env: PreviewEvaluator.Env) throws -> PreviewValue? {
        let handler = lock.withLock { storage.handlers[name] }
        guard let handler else { return nil }
        return try handler(evaluator, name, args, env)
    }

    static func isKnownView(_ symbol: String) -> Bool {
        if lock.withLock({ storage.entries[symbol] }) != nil { return true }
        return Self.builtIn[symbol] != nil
    }

    static func entry(for symbol: String) -> ComponentEntry? {
        if let e = lock.withLock({ storage.entries[symbol] }) { return e }
        return Self.builtIn[symbol]
    }

    static var all: [ComponentEntry] {
        let custom = lock.withLock { Array(storage.entries.values) }
        return (Array(Self.builtIn.values) + custom).sorted { $0.symbol < $1.symbol }
    }

    // MARK: Built-in table (mirrors PreviewEvaluator+Calls factories)

    private static let builtIn: [String: ComponentEntry] = {
        func e(_ s: String, args: [String] = [], level: ComponentSupportLevel = .supported,
               diag: String = "", workaround: String? = nil) -> (String, ComponentEntry) {
            (s, ComponentEntry(symbol: s, kind: .view, acceptedArgs: args,
                               supportLevel: level, diagnostics: diag, workaround: workaround))
        }
        return Dictionary(uniqueKeysWithValues: [
            e("Text", args: ["content"], diag: "文本，完整支持"),
            e("Image", args: ["systemName"], level: .approximate,
              diag: "仅 systemName；asset 图片显示占位"),
            e("Label", args: ["title", "systemImage"], diag: "标题 + SF Symbol"),
            e("VStack", args: ["alignment", "spacing"], diag: "垂直布局"),
            e("HStack", args: ["alignment", "spacing"], diag: "水平布局"),
            e("ZStack", args: ["alignment"], diag: "层叠布局"),
            e("LazyVStack", args: ["alignment", "spacing"], level: .approximate,
              diag: "按 VStack 近似渲染（不做懒加载）"),
            e("LazyHStack", args: ["alignment", "spacing"], level: .approximate,
              diag: "按 HStack 近似渲染（不做懒加载）"),
            e("Spacer", diag: "弹性空白"),
            e("Divider", diag: "分割线"),
            e("Group", diag: "透明容器"),
            e("NavigationStack", level: .approximate, diag: "按 Group 近似，不模拟导航栈"),
            e("NavigationView", level: .approximate, diag: "按 Group 近似，不模拟导航栈"),
            e("ScrollView", level: .approximate, diag: "内容直接渲染，可滚动近似"),
            e("Section", args: ["header", "footer"], diag: "分组容器"),
            e("List", diag: "列表容器"),
            e("ForEach", args: ["data", "id", "content"], diag: "循环渲染"),
            e("Button", args: ["action", "label"], diag: "按钮（action 不执行）"),
            e("Toggle", args: ["isOn"], diag: "开关，可交互"),
            e("TextField", args: ["text", "prompt"], diag: "输入框，可交互"),
            e("Slider", args: ["value", "in"], diag: "滑杆，可交互"),
            e("Circle", diag: "圆形"),
            e("Rectangle", diag: "矩形"),
            e("RoundedRectangle", args: ["cornerRadius"], diag: "圆角矩形"),
            e("Capsule", diag: "胶囊"),
            e("Ellipse", diag: "椭圆"),
            e("ProgressView", level: .approximate, diag: "进度样式近似"),
            e("Color", args: ["red", "green", "blue", "opacity"], diag: "颜色值"),
            e("Grid", level: .unsupported, diag: "暂不支持 Grid 布局",
              workaround: "用 LazyVGrid 替代，或等待注册表扩展"),
            e("Menu", level: .unsupported, diag: "暂不支持 Menu",
              workaround: "用 Button 近似表达入口"),
            e("Picker", level: .unsupported, diag: "暂不支持 Picker",
              workaround: "用 Text + 选项列表近似"),
            e("Gauge", level: .unsupported, diag: "暂不支持 Gauge",
              workaround: "用 ProgressView 近似"),
        ])
    }()
}

// MARK: - Modifier registry

enum ModifierRegistry {
    private final class Storage: @unchecked Sendable {
        var entries: [String: ComponentEntry] = [:]
    }
    private static let storage = Storage()
    private static let lock = NSLock()

    /// §15: register a new modifier's metadata without touching the core.
    static func register(symbol: String, acceptedArgs: [String] = [],
                        supportLevel: ComponentSupportLevel = .supported,
                        diagnostics: String = "") {
        lock.withLock {
            storage.entries[symbol] = ComponentEntry(symbol: symbol, kind: .modifier,
                acceptedArgs: acceptedArgs, supportLevel: supportLevel,
                diagnostics: diagnostics, workaround: nil)
        }
    }

    static func entry(for symbol: String) -> ComponentEntry? {
        if let e = lock.withLock({ storage.entries[symbol] }) { return e }
        return Self.builtIn[symbol]
    }

    static var all: [ComponentEntry] {
        let custom = lock.withLock { Array(storage.entries.values) }
        return (Array(Self.builtIn.values) + custom).sorted { $0.symbol < $1.symbol }
    }

    private static let builtIn: [String: ComponentEntry] = {
        func e(_ s: String, args: [String] = [], level: ComponentSupportLevel = .supported,
               diag: String = "") -> (String, ComponentEntry) {
            (s, ComponentEntry(symbol: s, kind: .modifier, acceptedArgs: args,
                               supportLevel: level, diagnostics: diag, workaround: nil))
        }
        return Dictionary(uniqueKeysWithValues: [
            e("padding", args: ["edges", "length"], diag: "内边距"),
            e("font", args: ["font"], diag: "字体"),
            e("fontWeight", args: ["weight"], diag: "字重"),
            e("bold", diag: "粗体"),
            e("italic", diag: "斜体"),
            e("foregroundColor", args: ["color"], diag: "前景色"),
            e("foregroundStyle", args: ["style"], level: .approximate, diag: "按前景色近似"),
            e("background", args: ["color", "shape"], diag: "背景"),
            e("tint", args: ["color"], diag: "着色"),
            e("frame", args: ["width", "height", "minWidth", "maxWidth", "alignment"], diag: "尺寸"),
            e("cornerRadius", args: ["radius"], diag: "圆角"),
            e("clipShape", args: ["shape"], level: .approximate, diag: "裁剪近似"),
            e("opacity", args: ["opacity"], diag: "不透明度"),
            e("shadow", args: ["radius"], level: .approximate, diag: "阴影近似"),
            e("lineLimit", args: ["number"], diag: "行数限制"),
            e("multilineTextAlignment", args: ["alignment"], diag: "文本对齐"),
            e("buttonStyle", args: ["style"], level: .cosmeticIgnore, diag: "按钮样式不影响 Lite 渲染"),
            e("imageScale", args: ["scale"], level: .cosmeticIgnore, diag: "图片缩放不影响 Lite 渲染"),
            e("minimumScaleFactor", args: ["factor"], level: .cosmeticIgnore, diag: "2.0 起静默忽略"),
            e("task", args: ["priority", "operation"], level: .unsupported, diag: "不执行异步任务"),
            e("onAppear", level: .unsupported, diag: "不执行生命周期回调"),
        ])
    }()
}

// MARK: - Shape / Style registries

enum ShapeRegistry {
    static let all: [ComponentEntry] = [
        .init(symbol: "Circle", kind: .shape, acceptedArgs: [], supportLevel: .supported, diagnostics: "圆形", workaround: nil),
        .init(symbol: "Rectangle", kind: .shape, acceptedArgs: [], supportLevel: .supported, diagnostics: "矩形", workaround: nil),
        .init(symbol: "RoundedRectangle", kind: .shape, acceptedArgs: ["cornerRadius"], supportLevel: .supported, diagnostics: "圆角矩形", workaround: nil),
        .init(symbol: "Capsule", kind: .shape, acceptedArgs: [], supportLevel: .supported, diagnostics: "胶囊", workaround: nil),
        .init(symbol: "Ellipse", kind: .shape, acceptedArgs: [], supportLevel: .supported, diagnostics: "椭圆", workaround: nil),
        .init(symbol: "Path", kind: .shape, acceptedArgs: [], supportLevel: .unsupported, diagnostics: "暂不支持 Path 绘制", workaround: "用 RoundedRectangle 近似"),
    ]

    static func entry(for symbol: String) -> ComponentEntry? {
        all.first { $0.symbol == symbol }
    }
}

enum StyleRegistry {
    static let all: [ComponentEntry] = [
        .init(symbol: "Material", kind: .style, acceptedArgs: ["ultraThin", "thin", "regular", "thick"], supportLevel: .approximate, diagnostics: "毛玻璃近似", workaround: nil),
        .init(symbol: "LinearGradient", kind: .style, acceptedArgs: ["colors"], supportLevel: .approximate, diagnostics: "渐变取首色近似", workaround: nil),
        .init(symbol: "AngularGradient", kind: .style, acceptedArgs: ["colors"], supportLevel: .unsupported, diagnostics: "暂不支持", workaround: "用 LinearGradient 近似"),
    ]
}

// MARK: - Facade

/// §15 + §24: one entry point for "what does Lite support?".
enum ComponentRegistry {
    static func entry(for symbol: String) -> ComponentEntry? {
        ViewRegistry.entry(for: symbol)
            ?? ModifierRegistry.entry(for: symbol)
            ?? ShapeRegistry.entry(for: symbol)
            ?? StyleRegistry.all.first { $0.symbol == symbol }
    }

    static func isKnownView(_ symbol: String) -> Bool {
        ViewRegistry.isKnownView(symbol)
    }

    /// §24 Compatibility Dashboard rows: every known symbol with its level.
    static func dashboardItems() -> [ComponentEntry] {
        (ViewRegistry.all + ModifierRegistry.all + ShapeRegistry.all + StyleRegistry.all)
            .sorted { $0.symbol < $1.symbol }
    }
}
