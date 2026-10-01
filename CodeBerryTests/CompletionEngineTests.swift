import XCTest
@testable import CodeBerry

/// §三十九: CompletionEngine — 本地 context-aware 补全.
final class CompletionEngineTests: XCTestCase {
    func testTextCallSuggestsStringLiteral() {
        let s = LocalCompletionEngine.contextSuggestions(beforeCaret: "VStack { Text(")
        XCTAssertTrue(s.contains { $0.display == "\" \"" })
        let lit = s.first { $0.display == "\" \"" }
        XCTAssertEqual(lit?.insert, "\"\"")
        XCTAssertEqual(lit?.caretBacktrack, 1)
    }

    func testDotSuggestsModifiers() {
        let s = LocalCompletionEngine.contextSuggestions(beforeCaret: "Text(\"hi\").")
        let displays = s.map(\.display)
        XCTAssertTrue(displays.contains("font"))
        XCTAssertTrue(displays.contains("padding"))
        // No leading dot: the dot is already typed.
        XCTAssertFalse(displays.contains { $0.hasPrefix(".") })
    }

    func testContainerBraceSuggestsViews() {
        let s = LocalCompletionEngine.contextSuggestions(beforeCaret: "var body: some View { VStack {")
        let displays = s.map(\.display)
        XCTAssertTrue(displays.contains("Spacer()"))
        XCTAssertTrue(displays.contains("Divider()"))
    }

    func testNoContextSuggestionsForPlainCode() {
        let s = LocalCompletionEngine.contextSuggestions(beforeCaret: "let x = 1\n")
        XCTAssertTrue(s.isEmpty)
    }

    func testKeywordCompletion() {
        let s = LocalCompletionEngine.suggestions(prefix: "st", textBeforeCaret: "st")
        XCTAssertTrue(s.contains { $0.display == "struct" })
        XCTAssertTrue(s.contains { $0.display == "static" })
    }

    func testCommonSymbolCompletion() {
        let s = LocalCompletionEngine.suggestions(prefix: "VSt", textBeforeCaret: "VSt")
        XCTAssertTrue(s.contains { $0.display == "VStack" })
    }

    func testSymbolIndexCompletion() {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift",
                         content: "struct HomeViewModel {}\n")
        let s = LocalCompletionEngine.suggestions(prefix: "HomeV",
                                                  textBeforeCaret: "HomeV",
                                                  symbolIndex: index)
        XCTAssertTrue(s.contains { $0.display == "HomeViewModel" })
    }

    func testNoDuplicateSuggestions() {
        let index = SymbolIndex()
        index.updateFile(relativePath: "A.swift", content: "struct Text {}\n")
        let s = LocalCompletionEngine.suggestions(prefix: "Tex",
                                                  textBeforeCaret: "Tex",
                                                  symbolIndex: index)
        let texts = s.filter { $0.display == "Text" }
        XCTAssertEqual(texts.count, 1)
    }

    func testEmptyPrefixYieldsContextOnly() {
        // No identifier typed: only context suggestions (no keyword spam).
        let s = LocalCompletionEngine.suggestions(prefix: "", textBeforeCaret: "Text(")
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0.display == "\" \"" || $0.display.hasPrefix("systemName") })
    }

    func testNestedCallFindsInnermost() {
        let s = LocalCompletionEngine.contextSuggestions(
            beforeCaret: "VStack { Text(\"a\" + String(")
        // Innermost unclosed call is String(, not Text(.
        XCTAssertFalse(s.contains { $0.display == "\" \"" })
    }
}
