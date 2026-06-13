import UIKit

/// Editor colors matching Xcode's "Default (Light/Dark)" theme.
@MainActor
enum CodeTheme {
    static let background = dynamic(light: 0xFFFFFF, dark: 0x1F1F24)
    static let plain      = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let keyword    = dynamic(light: 0xAD3DA4, dark: 0xFC5FA3)
    static let string     = dynamic(light: 0xD12F1B, dark: 0xFC6A5D)
    static let number     = dynamic(light: 0x272AD8, dark: 0xD0BF69)
    static let comment    = dynamic(light: 0x707F8C, dark: 0x6C7986)
    static let typeName   = dynamic(light: 0x0B4F79, dark: 0x5DD8FF)
    static let call       = dynamic(light: 0x3E8087, dark: 0x67B7A4)
    static let attribute  = dynamic(light: 0x78492A, dark: 0xFD8F3F)

    static let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let gutterFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: plain]
    }

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
        }
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

/// Lightweight regex-based Swift syntax highlighting. Applies attribute-only
/// edits to the text storage, so selection and the undo stack are untouched.
@MainActor
enum SwiftHighlighter {

    static let keywordList: [String] = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "precedencegroup", "protocol", "public", "rethrows", "static",
        "struct", "subscript", "typealias", "var", "break", "case", "catch",
        "continue", "default", "defer", "do", "else", "fallthrough", "for",
        "guard", "if", "in", "repeat", "return", "throw", "switch", "where",
        "while", "as", "any", "await", "async", "false", "is", "nil", "self",
        "Self", "super", "throws", "true", "try", "some", "actor", "nonisolated",
        "isolated", "lazy", "weak", "unowned", "indirect", "mutating",
        "nonmutating", "override", "required", "convenience", "dynamic", "final",
        "get", "set", "willSet", "didSet", "borrowing", "consuming"
    ]
    static let keywordSet = Set(keywordList)

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants; force-try is safe.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let numberRegex = regex(#"\b(?:0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#)
    private static let typeRegex = regex(#"\b[A-Z][A-Za-z0-9_]*\b"#)
    private static let callRegex = regex(#"\b([a-z_][A-Za-z0-9_]*)(?=\s*\()"#)
    private static let keywordRegex = regex(#"\b(?:"# + keywordList.joined(separator: "|") + #")\b"#)
    private static let attributeRegex = regex(#"@[A-Za-z_][A-Za-z0-9_]*"#)
    private static let directiveRegex = regex(#"#[A-Za-z_][A-Za-z0-9_]*"#)
    // Strings and comments resolved together so leftmost-match precedence
    // decides ambiguous cases ("//" inside a string, quotes inside a comment).
    private static let stringOrCommentRegex = regex(#"("""[\s\S]*?"""|"(?:[^"\\\n]|\\.)*"|//[^\n]*|/\*[\s\S]*?\*/)"#)

    static func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes(CodeTheme.baseAttributes, range: full)

        apply(numberRegex, color: CodeTheme.number, to: storage, in: full)
        apply(typeRegex, color: CodeTheme.typeName, to: storage, in: full)
        callRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let range = match?.range(at: 1) else { return }
            let word = text.substring(with: range)
            guard !keywordSet.contains(word) else { return }
            storage.addAttribute(.foregroundColor, value: CodeTheme.call, range: range)
        }
        apply(keywordRegex, color: CodeTheme.keyword, to: storage, in: full)
        apply(attributeRegex, color: CodeTheme.attribute, to: storage, in: full)
        apply(directiveRegex, color: CodeTheme.attribute, to: storage, in: full)

        stringOrCommentRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let range = match?.range else { return }
            let first = text.character(at: range.location)
            let color = first == UInt16(UInt8(ascii: "/")) ? CodeTheme.comment : CodeTheme.string
            storage.setAttributes([.font: CodeTheme.font, .foregroundColor: color], range: range)
        }

        storage.endEditing()
    }

    private static func apply(_ regex: NSRegularExpression, color: UIColor,
                              to storage: NSTextStorage, in range: NSRange) {
        regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
    }
}
