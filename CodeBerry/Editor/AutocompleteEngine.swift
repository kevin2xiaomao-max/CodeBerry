import Foundation

/// Word-completion suggestions from three sources: Swift keywords, common
/// SwiftUI/Foundation/UIKit symbols, and identifiers already in the document.
@MainActor
struct AutocompleteEngine {

    static let commonSymbols: [String] = [
        // SwiftUI types
        "View", "Text", "Image", "Label", "VStack", "HStack", "ZStack", "List",
        "ForEach", "NavigationStack", "NavigationSplitView", "NavigationLink",
        "ScrollView", "ScrollViewReader", "LazyVStack", "LazyHStack", "Grid",
        "GridRow", "Spacer", "Divider", "Button", "Toggle", "Slider", "Stepper",
        "TextField", "SecureField", "TextEditor", "Picker", "DatePicker", "Menu",
        "Form", "Section", "Group", "GroupBox", "GeometryReader", "Color", "Font",
        "Gradient", "LinearGradient", "Capsule", "Circle", "Rectangle",
        "RoundedRectangle", "Path", "Canvas", "TimelineView", "ProgressView",
        "ContentUnavailableView", "TabView", "Sheet", "Alert",
        // Property wrappers & macros
        "State", "Binding", "Bindable", "Observable", "ObservedObject",
        "StateObject", "EnvironmentObject", "Environment", "Published",
        "FocusState", "AppStorage", "SceneStorage", "MainActor", "Sendable",
        // Common modifiers / members
        "body", "padding", "background", "foregroundStyle", "foregroundColor",
        "font", "frame", "cornerRadius", "clipShape", "overlay", "onAppear",
        "onDisappear", "onChange", "onTapGesture", "onSubmit", "sheet", "alert",
        "toolbar", "navigationTitle", "navigationBarTitleDisplayMode",
        "animation", "transition", "opacity", "shadow", "ignoresSafeArea",
        "safeAreaInset", "listStyle", "listRowBackground", "buttonStyle",
        "pickerStyle", "labelStyle", "multilineTextAlignment", "lineLimit",
        "minimumScaleFactor", "aspectRatio", "resizable", "scaledToFit",
        "scaledToFill", "symbolRenderingMode", "fontWeight", "fontDesign",
        "bold", "italic", "monospaced", "textSelection", "contextMenu",
        "swipeActions", "refreshable", "searchable", "task", "disabled",
        "systemImage", "systemName", "spacing", "alignment", "leading",
        "trailing", "center", "infinity", "secondary", "primary", "accentColor",
        // Foundation / stdlib
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "URL", "URLSession", "URLRequest", "Data",
        "Date", "Calendar", "DateFormatter", "NumberFormatter", "UUID",
        "FileManager", "JSONDecoder", "JSONEncoder", "Codable", "Decodable",
        "Encodable", "Identifiable", "Hashable", "Equatable", "Comparable",
        "CaseIterable", "RawRepresentable", "CustomStringConvertible",
        "NotificationCenter", "UserDefaults", "Bundle", "Locale", "TimeZone",
        "TimeInterval", "Task", "AsyncStream", "AsyncThrowingStream",
        "withAnimation", "print", "append", "remove", "removeAll", "contains",
        "filter", "map", "compactMap", "flatMap", "reduce", "sorted", "first",
        "last", "count", "isEmpty", "joined", "split", "hasPrefix", "hasSuffix",
        "trimmingCharacters", "lowercased", "uppercased", "description",
        // UIKit (occasionally needed)
        "UIView", "UIColor", "UIImage", "UIFont", "UIViewController",
        "UIApplication", "UIScreen", "UIDevice"
    ]

    private static let identifierRegex = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]{2,}"#)

    /// Up to 10 completions for the word being typed.
    func suggestions(prefix: String, in documentText: String) -> [String] {
        guard prefix.count >= 2 else { return [] }
        let lowerPrefix = prefix.lowercased()

        var seen = Set<String>()
        var exactCase: [String] = []
        var otherCase: [String] = []

        func consider(_ word: String) {
            guard word != prefix, !seen.contains(word) else { return }
            if word.hasPrefix(prefix) {
                seen.insert(word)
                exactCase.append(word)
            } else if word.lowercased().hasPrefix(lowerPrefix) {
                seen.insert(word)
                otherCase.append(word)
            }
        }

        for word in SwiftHighlighter.keywordList { consider(word) }
        for word in Self.commonSymbols { consider(word) }

        let ns = documentText as NSString
        Self.identifierRegex.enumerateMatches(in: documentText,
                                              range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            guard let r = match?.range else { return }
            consider(ns.substring(with: r))
            if exactCase.count > 30 { stop.pointee = true }
        }

        exactCase.sort { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        otherCase.sort { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        return Array((exactCase + otherCase).prefix(10))
    }
}
