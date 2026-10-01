import Foundation
import Runestone
import UIKit

/// CodeBerry's editor theme for Runestone, in the spirit of Tomorrow.
/// Hardcoded colors (no asset catalog): picks a light or dark palette from
/// the current trait collection. Chinese input (marked text) gets a visible
/// background via `markedTextBackgroundColor`.
final class CodeBerryEditorTheme: Theme {
    private let dark: Bool

    init(userInterfaceStyle: UIUserInterfaceStyle = .unspecified) {
        if userInterfaceStyle == .unspecified {
            self.dark = UITraitCollection.current.userInterfaceStyle == .dark
        } else {
            self.dark = userInterfaceStyle == .dark
        }
    }

    // MARK: - Palette

    private var background: UIColor { dark ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1) : .white }
    private var foreground: UIColor { dark ? UIColor(red: 0.86, green: 0.87, blue: 0.88, alpha: 1) : UIColor(red: 0.24, green: 0.27, blue: 0.30, alpha: 1) }
    private var comment: UIColor { dark ? UIColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1) : UIColor(red: 0.55, green: 0.60, blue: 0.65, alpha: 1) }
    private var currentLine: UIColor { dark ? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1) : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1) }
    private var red: UIColor { dark ? UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1) : UIColor(red: 0.78, green: 0.20, blue: 0.20, alpha: 1) }
    private var orange: UIColor { dark ? UIColor(red: 0.95, green: 0.65, blue: 0.35, alpha: 1) : UIColor(red: 0.80, green: 0.45, blue: 0.10, alpha: 1) }
    private var yellow: UIColor { dark ? UIColor(red: 0.95, green: 0.80, blue: 0.40, alpha: 1) : UIColor(red: 0.65, green: 0.50, blue: 0.05, alpha: 1) }
    private var green: UIColor { dark ? UIColor(red: 0.60, green: 0.85, blue: 0.55, alpha: 1) : UIColor(red: 0.20, green: 0.55, blue: 0.25, alpha: 1) }
    private var aqua: UIColor { dark ? UIColor(red: 0.45, green: 0.80, blue: 0.85, alpha: 1) : UIColor(red: 0.15, green: 0.50, blue: 0.60, alpha: 1) }
    private var blue: UIColor { dark ? UIColor(red: 0.50, green: 0.65, blue: 1.00, alpha: 1) : UIColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1) }
    private var purple: UIColor { dark ? UIColor(red: 0.80, green: 0.60, blue: 1.00, alpha: 1) : UIColor(red: 0.55, green: 0.25, blue: 0.75, alpha: 1) }

    // MARK: - Theme

    var font: UIFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }
    var textColor: UIColor { foreground }

    var gutterBackgroundColor: UIColor { background }
    var gutterHairlineColor: UIColor { comment.withAlphaComponent(0.4) }
    var gutterHairlineWidth: CGFloat { 1 / UIScreen.main.scale }

    var lineNumberColor: UIColor { comment }
    var lineNumberFont: UIFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }

    var selectedLineBackgroundColor: UIColor { currentLine }
    var selectedLinesLineNumberColor: UIColor { foreground }
    var selectedLinesGutterBackgroundColor: UIColor { currentLine }

    var invisibleCharactersColor: UIColor { comment.withAlphaComponent(0.6) }

    var pageGuideHairlineColor: UIColor { comment.withAlphaComponent(0.3) }
    var pageGuideHairlineWidth: CGFloat { 1 / UIScreen.main.scale }
    var pageGuideBackgroundColor: UIColor { .clear }

    var markedTextBackgroundColor: UIColor { aqua.withAlphaComponent(0.25) }
    var markedTextBackgroundCornerRadius: CGFloat { 4 }

    /// Matches Runestone's tree-sitter highlight names (longest prefix wins).
    func textColor(for rawHighlightName: String) -> UIColor? {
        let name = rawHighlightName.lowercased()
        func has(_ prefixes: String...) -> Bool {
            prefixes.contains { name == $0 || name.hasPrefix($0 + ".") }
        }
        if has("comment") { return comment }
        if has("string", "constant.character") { return green }
        if has("number", "constant.builtin", "constant") { return orange }
        if has("keyword") { return purple }
        if has("function", "constructor", "method") { return blue }
        if has("type") { return yellow }
        if has("property") { return aqua }
        if has("variable.builtin") { return red }
        if has("operator", "punctuation") { return foreground.withAlphaComponent(0.8) }
        return nil
    }

    func font(for highlightName: String) -> UIFont? { nil }

    func fontTraits(for rawHighlightName: String) -> FontTraits {
        let name = rawHighlightName.lowercased()
        return (name == "keyword" || name.hasPrefix("keyword.")) ? .bold : []
    }

    func shadow(for highlightName: String) -> NSShadow? { nil }

    @available(iOS 16, *)
    func highlightedRange(forFoundTextRange foundTextRange: NSRange,
                          ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange? {
        switch style {
        case .found:
            return HighlightedRange(range: foundTextRange,
                                    color: yellow.withAlphaComponent(0.45))
        case .highlighted:
            return HighlightedRange(range: foundTextRange, color: yellow)
        case .normal:
            return nil
        @unknown default:
            return nil
        }
    }
}
