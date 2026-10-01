import XCTest
@testable import CodeBerry

/// M4: Security policy — HTTPS-only, executable detection, token redaction.
final class SecurityPolicyTests: XCTestCase {
    func testHttpsOnly() {
        XCTAssertTrue(SecurityPolicy.isAllowedURL(URL(string: "https://api.github.com")!))
        XCTAssertFalse(SecurityPolicy.isAllowedURL(URL(string: "http://api.github.com")!))
        XCTAssertFalse(SecurityPolicy.isAllowedURL(URL(string: "ftp://x.com")!))
        XCTAssertFalse(SecurityPolicy.isAllowedURL(URL(string: "https://")!))
    }

    func testExecutableExtensionDetected() {
        XCTAssertTrue(SecurityPolicy.isExecutableFile(
            at: URL(fileURLWithPath: "/tmp/x.sh")))
        XCTAssertTrue(SecurityPolicy.isExecutableFile(
            at: URL(fileURLWithPath: "/tmp/lib.dylib")))
        XCTAssertFalse(SecurityPolicy.isExecutableFile(
            at: URL(fileURLWithPath: "/tmp/App.swift")))
    }

    func testExecutableBitDetected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cb-exec-test-\(UUID().uuidString).txt")
        try "hi".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(SecurityPolicy.isExecutableFile(at: url))
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
        XCTAssertTrue(SecurityPolicy.isExecutableFile(at: url))
    }

    func testTokenRedaction() {
        let raw = "Authorization: Bearer github_pat_abc123XYZ and ghp_deadbeef"
        let out = SecurityPolicy.redacted(raw)
        XCTAssertFalse(out.contains("github_pat_abc123XYZ"))
        XCTAssertFalse(out.contains("ghp_deadbeef"))
        XCTAssertTrue(out.contains("***REDACTED***"))
    }

    func testNoExecutionInvariant() {
        XCTAssertTrue(SecurityPolicy.assertNoExecutionPossible(
            at: URL(fileURLWithPath: "/tmp")))
    }
}
