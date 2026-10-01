import Runestone
import SwiftUI
import TreeSitterSwiftRunestone
import UIKit

/// Lets SwiftUI views (coding bar, suggestions) drive the Runestone text view.
@MainActor
final class EditorController {
    weak var textView: TextView?

    func insert(_ snippet: String) {
        textView?.insertText(snippet)
    }

    /// Moves the caret by a character offset (Coding Bar ← →).
    func moveCaret(by offset: Int) {
        guard let tv = textView else { return }
        let loc = max(0, min((tv.text as NSString).length, tv.selectedRange.location + offset))
        tv.selectedRange = NSRange(location: loc, length: 0)
    }

    /// Replaces the identifier being typed at the caret with `word`.
    func applyCompletion(_ word: String) {
        guard let tv = textView else { return }
        let ns = tv.text as NSString
        let caret = tv.selectedRange.location
        var start = caret
        while start > 0, Self.isIdentifierChar(ns.character(at: start - 1)) { start -= 1 }
        tv.selectedRange = NSRange(location: start, length: caret - start)
        tv.insertText(word)
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }

    /// Caret offset in the document, or nil when there's a selection.
    var caretOffset: Int? {
        guard let tv = textView, tv.selectedRange.length == 0 else { return nil }
        return tv.selectedRange.location
    }

    /// Text before the caret (for context-aware suggestions).
    var textBeforeCaret: String {
        guard let tv = textView else { return "" }
        let ns = tv.text as NSString
        return ns.substring(to: min(tv.selectedRange.location, ns.length))
    }

    nonisolated static func isIdentifierChar(_ c: unichar) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95
    }
}

/// The code editor: Runestone (Tree-sitter highlighting, line numbers,
/// find/replace) with the buffer bound to the workspace store.
///
/// The Coding Bar above the keyboard is a plain toolbar — it never intercepts
/// keystrokes, so Chinese (and other marked-text) input is unaffected.
@MainActor
struct RunestoneEditorView: UIViewRepresentable {
    @Binding var text: String
    let fileID: String
    let controller: EditorController
    /// Diagnostic underlines, refreshed by the parent.
    var diagnosticRanges: [HighlightedRange] = []
    /// When set to a 1-based line, the editor scrolls there once.
    @Binding var navigateToLine: Int?
    var onCaretWordChange: (String) -> Void = { _ in }
    var onTextChange: () -> Void = {}

    func makeUIView(context: Context) -> TextView {
        let tv = TextView()
        tv.showLineNumbers = true
        tv.isLineWrappingEnabled = false
        tv.isFindInteractionEnabled = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.keyboardAppearance = .default
        tv.editorDelegate = context.coordinator
        applyAppearance(tv)
        controller.textView = tv
        return tv
    }

    func updateUIView(_ tv: TextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        applyAppearance(tv)
        if context.coordinator.currentFileID != fileID {
            context.coordinator.currentFileID = fileID
            context.coordinator.setText(text, in: tv, resetScroll: true)
            applyLanguageMode(tv)
        } else if tv.text != text {
            // External change: the file was rewritten on disk.
            context.coordinator.setText(text, in: tv, resetScroll: false)
        }
        tv.highlightedRanges = diagnosticRanges
        if let line = navigateToLine {
            navigateToLine = nil
            _ = tv.goToLine(max(0, line - 1))
        }
    }

    private func applyAppearance(_ tv: TextView) {
        let style = tv.traitCollection.userInterfaceStyle
        tv.theme = CodeBerryEditorTheme(userInterfaceStyle: style)
        tv.backgroundColor = style == .dark
            ? UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1) : .white
        tv.insertionPointColor = style == .dark ? .white : .black
    }

    private func applyLanguageMode(_ tv: TextView) {
        if fileID.hasSuffix(".swift") {
            tv.setLanguageMode(TreeSitterLanguageMode(language: .swift)) { _ in }
        } else {
            tv.setLanguageMode(PlainTextLanguageMode()) { _ in }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // @MainActor so it can touch `parent` (SwiftUI Views are @MainActor).
    // The TextViewDelegate witnesses are marked nonisolated (the protocol
    // is nonisolated) and re-enter via MainActor.assumeIsolated — Runestone
    // always invokes them on the main thread.
    @MainActor
    final class Coordinator: NSObject, TextViewDelegate {
        var parent: RunestoneEditorView
        var currentFileID: String?
        private var suppressCallbacks = false

        init(_ parent: RunestoneEditorView) { self.parent = parent }

        func setText(_ newText: String, in tv: TextView, resetScroll: Bool) {
            suppressCallbacks = true
            let oldSelection = tv.selectedRange
            tv.text = newText
            tv.undoManager?.removeAllActions()
            if resetScroll {
                tv.selectedRange = NSRange(location: 0, length: 0)
                tv.contentOffset = .zero
            } else {
                let limit = (newText as NSString).length
                tv.selectedRange = NSRange(location: min(oldSelection.location, limit), length: 0)
            }
            suppressCallbacks = false
        }

        // MARK: TextViewDelegate

        nonisolated func textViewDidChange(_ textView: TextView) {
            MainActor.assumeIsolated {
                guard !self.suppressCallbacks else { return }
                self.parent.text = textView.text
                self.parent.onTextChange()
            }
        }

        nonisolated func textViewDidChangeSelection(_ textView: TextView) {
            MainActor.assumeIsolated {
                guard !self.suppressCallbacks else { return }
                self.reportCaretWord(textView)
            }
        }

        nonisolated func textView(_ textView: TextView, shouldChangeTextIn range: NSRange,
                      replacementText t: String) -> Bool {
            let ns = textView.text as NSString
            let prev = range.location > 0
                ? ns.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
            let nextIndex = range.location + range.length
            let next = nextIndex < ns.length
                ? ns.substring(with: NSRange(location: nextIndex, length: 1)) : ""

            // Auto-indent on newline, expanding `{` + newline Xcode-style.
            if t == "\n" {
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let lineHead = ns.substring(with: NSRange(location: lineRange.location,
                                                          length: range.location - lineRange.location))
                let indent = String(lineHead.prefix { $0 == " " })
                if prev == "{" && next == "}" {
                    textView.insertText("\n" + indent + "    \n" + indent)
                    textView.selectedRange = NSRange(location: range.location + 1 + indent.count + 4,
                                                     length: 0)
                    return false
                }
                if prev == "{" {
                    textView.insertText("\n" + indent + "    ")
                    return false
                }
                if !indent.isEmpty {
                    textView.insertText("\n" + indent)
                    return false
                }
                return true
            }

            // Close bracket/quote pairs as they're opened.
            let pairs = ["{": "}", "(": ")", "[": "]", "\"": "\""]
            if range.length == 0, let close = pairs[t] {
                if t == "\"" && next == "\"" {
                    textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                    return false
                }
                textView.insertText(t + close)
                textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }

            // Skip over a closer that's already there.
            if range.length == 0, ["}", ")", "]"].contains(t), next == t {
                textView.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }

            return true
        }

        // MARK: Helpers

        private func reportCaretWord(_ textView: TextView) {
            let ns = textView.text as NSString
            let selection = textView.selectedRange
            guard selection.length == 0, selection.location <= ns.length else {
                parent.onCaretWordChange("")
                return
            }
            var start = selection.location
            while start > 0, EditorController.isIdentifierChar(ns.character(at: start - 1)) {
                start -= 1
            }
            parent.onCaretWordChange(ns.substring(with: NSRange(location: start,
                                                                length: selection.location - start)))
        }
    }
}
