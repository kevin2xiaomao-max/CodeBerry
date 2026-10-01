import XCTest
@testable import CodeBerry

/// M4: Session Store — save / load / clear round-trip.
final class SessionStoreTests: XCTestCase {
    override func tearDown() {
        SessionStore.clear()
        super.tearDown()
    }

    func testEmptyByDefault() {
        SessionStore.clear()
        let s = SessionStore.load()
        XCTAssertNil(s.projectFolder)
        XCTAssertNil(s.openFilePath)
        XCTAssertTrue(s.cursorLines.isEmpty)
    }

    func testRoundTrip() {
        let session = WorkspaceSession(
            projectFolder: "/tmp/Proj",
            openFilePath: "Sources/A.swift",
            cursorLines: ["Sources/A.swift": 42],
            selectedTab: 2)
        SessionStore.save(session)
        let loaded = SessionStore.load()
        XCTAssertEqual(loaded, session)
    }

    func testCursorLineUpdate() {
        var s = SessionStore.load()
        s.cursorLines["a.swift"] = 10
        SessionStore.save(s)
        XCTAssertEqual(SessionStore.load().cursorLines["a.swift"], 10)
    }

    func testClear() {
        SessionStore.save(WorkspaceSession(projectFolder: "/x", openFilePath: nil,
                                           cursorLines: [:], selectedTab: 1))
        SessionStore.clear()
        XCTAssertEqual(SessionStore.load(), .empty)
    }
}
