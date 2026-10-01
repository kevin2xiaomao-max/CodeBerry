import SwiftUI

/// iPhone Coding Bar (§12, P0): fixed above the soft keyboard.
///
/// Fixed keys: Tab  { }  ( )  [ ]  .  ,  :  "  ←  →
/// Plus context-aware suggestions (e.g. after `Text(` → `" "`, `.font`, …).
/// It is a plain toolbar — it never intercepts keystrokes, so Chinese
/// (marked-text) input is unaffected.
struct CodingBarView: View {
    /// Context-aware suggestions for the caret position (may be empty).
    let suggestions: [LocalCompletionEngine.Suggestion]
    let onSuggestion: (LocalCompletionEngine.Suggestion) -> Void
    let onKey: (CodingBarKey) -> Void
    let onDismissKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.display) { s in
                            Button {
                                onSuggestion(s)
                            } label: {
                                Text(s.display)
                                    .font(.system(size: 14, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .controlSize(.small)
                            .tint(.accentColor)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                Divider()
            }
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(CodingBarKey.allCases) { key in
                            Button {
                                onKey(key)
                            } label: {
                                Text(key.label)
                                    .font(.system(size: 15, design: .monospaced))
                                    .frame(minWidth: 24)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                Divider().frame(height: 22)
                Button {
                    onDismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .padding(.horizontal, 10)
            }
        }
        .background(.bar)
    }
}

/// The fixed key set from §12.
enum CodingBarKey: String, CaseIterable, Identifiable {
    case tab, openBrace, closeBrace
    case openParen, closeParen
    case openBracket, closeBracket
    case dot, comma, colon, quote
    case left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tab: return "Tab"
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .openParen: return "("
        case .closeParen: return ")"
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .dot: return "."
        case .comma: return ","
        case .colon: return ":"
        case .quote: return "\""
        case .left: return "←"
        case .right: return "→"
        }
    }

    /// Text inserted for this key (nil = handled specially by the caller).
    var insertText: String? {
        switch self {
        case .tab: return "    "
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .openParen: return "("
        case .closeParen: return ")"
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .dot: return "."
        case .comma: return ","
        case .colon: return ":"
        case .quote: return "\""
        case .left, .right: return nil
        }
    }
}
