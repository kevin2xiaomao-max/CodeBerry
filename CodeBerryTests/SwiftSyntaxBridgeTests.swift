import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import XCTest
@testable import CodeBerry

/// §三十九: SwiftSyntaxBridge — 解析 / 诊断 / 位置转换桥接.
final class SwiftSyntaxBridgeTests: XCTestCase {
    func testParseValidSource() {
        let tree = Parser.parse(source: "struct Foo { let x = 1 }\n")
        XCTAssertFalse(tree.hasError)
        XCTAssertTrue(tree.statements.count == 1)
    }

    func testParseDetectsError() {
        let tree = Parser.parse(source: "struct Foo { let x = \n")
        XCTAssertTrue(tree.hasError)
    }

    func testDiagnosticsForBrokenCode() {
        let tree = Parser.parse(source: "func broken( {\n  let x = 1\n")
        let diags = ParseDiagnosticsGenerator.diagnostics(for: tree)
        let errors = diags.filter { $0.diagMessage.severity == .error }
        XCTAssertFalse(errors.isEmpty, "expected at least one parse error")
    }

    func testNoDiagnosticsForCleanCode() {
        let tree = Parser.parse(source: "struct Foo {\n  let x = 1\n}\n")
        let diags = ParseDiagnosticsGenerator.diagnostics(for: tree)
            .filter { $0.diagMessage.severity == .error || $0.diagMessage.severity == .warning }
        XCTAssertTrue(diags.isEmpty)
    }

    func testDiagnosticPositionMapping() {
        // Error on line 2.
        let source = "struct Foo {\n  let x = \n}\n"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "t.swift", tree: tree)
        let diags = ParseDiagnosticsGenerator.diagnostics(for: tree)
        XCTAssertFalse(diags.isEmpty)
        let loc = converter.location(for: diags[0].position)
        XCTAssertEqual(loc.line, 2)
        XCTAssertGreaterThanOrEqual(loc.column, 1)
    }

    func testDiagnosticMessageAvailable() {
        let tree = Parser.parse(source: "let x = \n")
        let diags = ParseDiagnosticsGenerator.diagnostics(for: tree)
        XCTAssertFalse(diags.isEmpty)
        XCTAssertFalse(diags[0].diagMessage.message.isEmpty)
    }

    func testInlineEngineEndToEnd() {
        // The app's engine on top of the bridge.
        let diags = InlineDiagnosticsEngine.diagnose(source: "struct Foo {\n  let x = \n}\n")
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.allSatisfy { $0.tier == .syntax })
        XCTAssertEqual(diags[0].line, 2)
        XCTAssertFalse(diags[0].message.isEmpty)
    }

    func testHighlightRanges() {
        let source = "struct Foo {\n  let x = \n}\n"
        let diags = InlineDiagnosticsEngine.diagnose(source: source)
        let ranges = InlineDiagnosticsEngine.highlightRanges(for: diags, in: source)
        XCTAssertFalse(ranges.isEmpty)
        // The range must lie inside the document.
        let ns = source as NSString
        for r in ranges {
            XCTAssertTrue(NSMaxRange(r.range) <= ns.length)
        }
    }
}
