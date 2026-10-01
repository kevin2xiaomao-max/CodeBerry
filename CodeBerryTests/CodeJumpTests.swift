import XCTest
@testable import CodeBerry

/// P1-1 regression: Preview → Code navigation switches to the Code tab,
/// opens the right file, and requests the line jump the editor consumes.
/// (Before the fix, `onJumpToCode` posted the notification with a nil
/// object and nothing selected the Code tab or navigated.)
@MainActor
final class CodeJumpTests: XCTestCase {

    private var tmp: URL!
    private var store: WorkspaceStore!

    override func setUp() async throws {
        try await super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-jump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        store = WorkspaceStore(rootURL: tmp)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults.standard.removeObject(forKey: "lastProjectPath")
        UserDefaults.standard.removeObject(forKey: "lastOpenFilePath")
        try await super.tearDown()
    }

    /// The jump notification carries a real CodeJumpRequest payload (not nil).
    func testJumpNotificationCarriesPayload() {
        let exp = expectation(description: "jump notification")
        var received: CodeJumpRequest?
        let token = NotificationCenter.default.addObserver(
            forName: .codeBerryJumpToCode, object: nil, queue: nil) { note in
                received = note.object as? CodeJumpRequest
                exp.fulfill()
            }
        NotificationCenter.default.post(
            name: .codeBerryJumpToCode,
            object: CodeJumpRequest(path: "GH/A.swift", line: 7))
        wait(for: [exp], timeout: 2)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(received, CodeJumpRequest(path: "GH/A.swift", line: 7))
    }

    /// handleCodeJumpRequest: opens the right file, requests the line jump,
    /// and reports the Code tab index for the TabView to select.
    func testHandleCodeJumpRequest() throws {
        let project = tmp.appendingPathComponent("GH")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("struct A {}".utf8).write(to: project.appendingPathComponent("A.swift"))
        try Data("struct B {}".utf8).write(to: project.appendingPathComponent("B.swift"))
        store.openProject("GH")

        // A different file is open: the jump must switch files.
        store.openFile("GH/B.swift")
        XCTAssertEqual(store.openFilePath, "GH/B.swift")

        let tab = store.handleCodeJumpRequest(CodeJumpRequest(path: "GH/A.swift", line: 42))
        XCTAssertEqual(tab, 1, "must select the Code tab")
        XCTAssertEqual(store.openFilePath, "GH/A.swift")
        XCTAssertEqual(store.pendingLineJump, 42)

        // The editor consumes the jump exactly once.
        XCTAssertEqual(store.consumeLineJump(), 42)
        XCTAssertNil(store.consumeLineJump())
        XCTAssertNil(store.pendingLineJump)
    }

    /// Jumping to the already-open file still requests the line jump.
    func testJumpToOpenFileStillJumpsLine() throws {
        let project = tmp.appendingPathComponent("GH")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("struct A {}".utf8).write(to: project.appendingPathComponent("A.swift"))
        store.openProject("GH")
        store.openFile("GH/A.swift")

        _ = store.handleCodeJumpRequest(CodeJumpRequest(path: "GH/A.swift", line: 3))
        XCTAssertEqual(store.openFilePath, "GH/A.swift")
        XCTAssertEqual(store.pendingLineJump, 3)
    }
}
