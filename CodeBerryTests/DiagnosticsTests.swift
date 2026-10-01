import XCTest
@testable import CodeBerry

/// §三十九: Diagnostics — 三层中文诊断标签.
final class DiagnosticsTests: XCTestCase {
    func testTierChineseLabels() {
        XCTAssertEqual(DiagnosticTier.syntax.chineseLabel, "语法错误")
        XCTAssertEqual(DiagnosticTier.previewSemantic.chineseLabel,
                       "CodeBerry Preview 尚未实现此语义")
        XCTAssertEqual(DiagnosticTier.unsupportedRuntime.chineseLabel, "需要 Mock")
    }

    func testCleanCodeHasNoDiagnostics() {
        let diags = InlineDiagnosticsEngine.diagnose(
            source: "import SwiftUI\nstruct Foo: View {\n  var body: some View { Text(\"hi\") }\n}\n")
        XCTAssertTrue(diags.isEmpty)
    }

    func testBrokenCodeReportsSyntaxTier() {
        let diags = InlineDiagnosticsEngine.diagnose(source: "struct Foo {\n  let x = \n}\n")
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.allSatisfy { $0.tier == .syntax })
    }

    func testMessagesAreChineseLabeled() {
        let diags = InlineDiagnosticsEngine.diagnose(source: "func f( {\n}\n")
        XCTAssertFalse(diags.isEmpty)
        for d in diags {
            XCTAssertTrue(d.message.hasPrefix("语法错误")
                          || d.message == "缺少符号"
                          || d.message.contains("缺少")
                          || d.message.contains("需要"),
                          "message not Chinese-labeled: \(d.message)")
        }
    }

    func testMissingBraceMessage() {
        // Common mistake: unclosed brace.
        let diags = InlineDiagnosticsEngine.diagnose(source: "struct Foo {\n  let x = 1\n")
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.contains { $0.message.contains("}") || $0.message.contains("缺少") })
    }

    func testDiagnosticsSortedByPosition() {
        let diags = InlineDiagnosticsEngine.diagnose(
            source: "let a = \nlet b = \n")
        let positions = diags.map { ($0.line, $0.column) }
        let sorted = positions.sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1 < b.1
        }
        // (Int, Int) tuples aren't Equatable — compare element-wise.
        XCTAssertTrue(positions.elementsEqual(sorted, by: { $0.0 == $1.0 && $0.1 == $1.1 }),
                      "diagnostics not sorted by position: \(positions)")
    }

    func testWarningVsErrorFlag() {
        // Unused variable etc. may surface as warnings; at minimum the flag
        // must round-trip the parser severity.
        let diags = InlineDiagnosticsEngine.diagnose(source: "struct Foo {\n  let x = \n}\n")
        XCTAssertTrue(diags.contains { !$0.isWarning })
    }

    func testLineColumnAreOneBased() {
        let diags = InlineDiagnosticsEngine.diagnose(source: "let x = \n")
        XCTAssertFalse(diags.isEmpty)
        XCTAssertGreaterThanOrEqual(diags[0].line, 1)
        XCTAssertGreaterThanOrEqual(diags[0].column, 1)
    }
}
