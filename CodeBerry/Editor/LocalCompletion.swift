import Foundation

/// Local, offline code completion (§M2: Completion).
/// Sources, in priority order:
/// 1. Context-aware suggestions (e.g. after `Text(` → `" "`, `.font`, …)
/// 2. Project symbol index (type/function names)
/// 3. Swift keywords
/// No network, no AI — everything is computed on-device.
struct LocalCompletionEngine {
    /// A suggestion with an optional trailing snippet to insert.
    struct Suggestion: Hashable {
        let display: String
        /// Text inserted when the suggestion replaces the current prefix.
        let insert: String
        /// If true, the caret lands inside the inserted text (for pairs).
        let caretBacktrack: Int

        init(_ display: String, insert: String? = nil, caretBacktrack: Int = 0) {
            self.display = display
            self.insert = insert ?? display
            self.caretBacktrack = caretBacktrack
        }
    }

    /// - Parameters:
    ///   - prefix: identifier fragment before the caret (may be empty)
    ///   - textBeforeCaret: full text before the caret, for context analysis
    ///   - symbolIndex: project symbols (may be nil)
    static func suggestions(prefix: String,
                            textBeforeCaret: String,
                            symbolIndex: SymbolIndex? = nil) -> [Suggestion] {
        var out: [Suggestion] = []

        // 1. Context-aware.
        out.append(contentsOf: contextSuggestions(beforeCaret: textBeforeCaret))

        // 2. Symbol index.
        if let index = symbolIndex, !prefix.isEmpty {
            for sym in index.symbols(matching: prefix, limit: 12) {
                out.append(Suggestion(sym.name))
            }
        }

        // 3. Common SwiftUI / Foundation symbols (offline word list).
        if !prefix.isEmpty {
            let lower = prefix.lowercased()
            for word in Self.commonSymbols where word.lowercased().hasPrefix(lower) {
                out.append(Suggestion(word))
            }
        }

        // 4. Keywords.
        let lower = prefix.lowercased()
        for kw in Self.keywords where kw.hasPrefix(lower) && !lower.isEmpty {
            out.append(Suggestion(kw))
        }

        // De-duplicate, keep order.
        var seen = Set<String>()
        return out.filter { seen.insert($0.display).inserted }.prefix(20).map { $0 }
    }

    // MARK: - Context

    /// Looks at the code immediately before the caret and suggests what the
    /// spec's Coding Bar describes. Every suggestion's `insert` text is valid
    /// to insert literally at the caret.
    static func contextSuggestions(beforeCaret: String) -> [Suggestion] {
        let trimmed = beforeCaret.replacingOccurrences(of: "\\s+$",
                                                       with: "",
                                                       options: .regularExpression)
        // Inside an argument list: `Text(` → suggest a string literal.
        if let call = lastCallName(in: trimmed) {
            switch call {
            case "Text":
                return [Suggestion("\" \"", insert: "\"\"", caretBacktrack: 1)]
            case "Image":
                return [Suggestion("systemName: \"…\"", insert: "systemName: \"\"", caretBacktrack: 1)]
            default:
                break
            }
        }
        // Right after an opening container brace: suggest common views.
        if trimmed.hasSuffix("VStack {") || trimmed.hasSuffix("HStack {")
            || trimmed.hasSuffix("ZStack {") || trimmed.hasSuffix("List {")
            || trimmed.hasSuffix("Form {") || trimmed.hasSuffix("body {") {
            return [Suggestion("Text(\"…\")", insert: "Text(\"\")", caretBacktrack: 2),
                    Suggestion("Image"),
                    Suggestion("Spacer()"),
                    Suggestion("Divider()")]
        }
        // After a dot (already typed): suggest common modifiers, no dot.
        if trimmed.hasSuffix(".") {
            return [Suggestion("font"),
                    Suggestion("foregroundStyle"),
                    Suggestion("padding"),
                    Suggestion("frame"),
                    Suggestion("background"),
                    Suggestion("onTapGesture")]
        }
        return []
    }

    /// Finds the innermost unclosed call, e.g. "Text" for `VStack { Text(`.
    private static func lastCallName(in code: String) -> String? {
        // Walk backwards to the nearest unmatched "(".
        var depth = 0
        var idx = code.endIndex
        while idx > code.startIndex {
            idx = code.index(before: idx)
            let ch = code[idx]
            if ch == ")" { depth += 1 }
            else if ch == "(" {
                if depth == 0 {
                    // Identifier immediately before "(".
                    var start = idx
                    while start > code.startIndex {
                        let prev = code.index(before: start)
                        let c = code[prev]
                        if c.isLetter || c.isNumber || c == "_" { start = prev }
                        else { break }
                    }
                    let name = String(code[start..<idx])
                    return name.isEmpty ? nil : name
                }
                depth -= 1
            }
        }
        return nil
    }

    // MARK: - Keywords

    static let keywords = [
        "func", "var", "let", "struct", "class", "enum", "protocol",
        "extension", "import", "return", "if", "else", "guard", "for",
        "while", "switch", "case", "default", "break", "continue",
        "init", "deinit", "self", "Self", "true", "false", "nil",
        "do", "try", "catch", "throw", "throws", "async", "await",
        "private", "public", "internal", "fileprivate", "static",
    ]

    /// Offline word list of common SwiftUI / Foundation / stdlib symbols.
    static let commonSymbols = [
        "View", "Text", "Image", "Label", "VStack", "HStack", "ZStack", "List",
        "ForEach", "NavigationStack", "NavigationSplitView", "NavigationLink",
        "ScrollView", "LazyVStack", "LazyHStack", "Grid", "GridRow",
        "Spacer", "Divider", "Button", "Toggle", "Slider", "Stepper",
        "TextField", "SecureField", "Picker", "DatePicker", "Menu",
        "Form", "Section", "Group", "GroupBox", "GeometryReader", "Color", "Font",
        "Gradient", "LinearGradient", "Capsule", "Circle", "Rectangle",
        "RoundedRectangle", "Path", "Canvas", "ProgressView",
        "ContentUnavailableView", "TabView",
        "State", "Binding", "Bindable", "Observable", "ObservedObject",
        "StateObject", "Environment", "Published",
        "FocusState", "AppStorage", "SceneStorage", "MainActor", "Sendable",
        "body", "padding", "background", "foregroundStyle", "foregroundColor",
        "font", "frame", "cornerRadius", "clipShape", "overlay", "onAppear",
        "onDisappear", "onChange", "onTapGesture", "onSubmit", "sheet", "alert",
        "toolbar", "navigationTitle", "navigationBarTitleDisplayMode",
        "animation", "transition", "opacity", "shadow", "ignoresSafeArea",
        "safeAreaInset", "listStyle", "buttonStyle", "pickerStyle",
        "lineLimit", "aspectRatio", "resizable", "scaledToFit", "scaledToFill",
        "bold", "italic", "monospaced", "textSelection", "contextMenu",
        "swipeActions", "refreshable", "searchable", "task", "disabled",
        "systemImage", "systemName", "spacing", "alignment",
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "URL", "URLSession", "URLRequest", "Data",
        "Date", "Calendar", "DateFormatter", "UUID",
        "FileManager", "JSONDecoder", "JSONEncoder", "Codable", "Decodable",
        "Encodable", "Identifiable", "Hashable", "Equatable",
        "NotificationCenter", "UserDefaults", "Bundle", "Locale",
        "Task", "AsyncStream",
        "print", "append", "remove", "removeAll", "contains",
        "filter", "map", "compactMap", "flatMap", "reduce", "sorted", "first",
        "last", "count", "isEmpty", "joined", "split", "hasPrefix", "hasSuffix",
        "description",
    ]
}
