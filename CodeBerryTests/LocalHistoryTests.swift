import XCTest
@testable import CodeBerry

/// M4: Local History — record, dedupe, bound, restore.
final class LocalHistoryTests: XCTestCase {
    private func makeStore() -> LocalHistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cb-history-test-\(UUID().uuidString)", isDirectory: true)
        return LocalHistoryStore(directory: dir)
    }

    func testRecordAndRead() {
        let store = makeStore()
        store.recordSync(path: "a.swift", content: "let x = 1\n")
        let revs = store.revisions(for: "a.swift")
        XCTAssertEqual(revs.count, 1)
        XCTAssertEqual(revs[0].content, "let x = 1\n")
        XCTAssertEqual(revs[0].path, "a.swift")
    }

    func testIdenticalContentDeduped() {
        let store = makeStore()
        store.recordSync(path: "a.swift", content: "same\n")
        store.recordSync(path: "a.swift", content: "same\n")
        XCTAssertEqual(store.revisions(for: "a.swift").count, 1)
    }

    func testMultipleRevisionsKeptInOrder() {
        let store = makeStore()
        store.recordSync(path: "a.swift", content: "v1\n")
        store.recordSync(path: "a.swift", content: "v2\n")
        store.recordSync(path: "a.swift", content: "v3\n")
        let revs = store.revisions(for: "a.swift")
        XCTAssertEqual(revs.map(\.content), ["v1\n", "v2\n", "v3\n"])
    }

    func testPerFileIsolation() {
        let store = makeStore()
        store.recordSync(path: "a.swift", content: "a\n")
        store.recordSync(path: "b.swift", content: "b\n")
        XCTAssertEqual(store.revisions(for: "a.swift").count, 1)
        XCTAssertEqual(store.revisions(for: "b.swift").count, 1)
        XCTAssertTrue(store.revisions(for: "c.swift").isEmpty)
    }

    func testBoundedAtMaxRevisions() {
        let store = makeStore()
        for i in 0..<(LocalHistoryStore.maxRevisionsPerFile + 10) {
            store.recordSync(path: "a.swift", content: "v\(i)\n")
        }
        let revs = store.revisions(for: "a.swift")
        XCTAssertEqual(revs.count, LocalHistoryStore.maxRevisionsPerFile)
        // Oldest evicted, newest kept.
        XCTAssertEqual(revs.last?.content, "v\(LocalHistoryStore.maxRevisionsPerFile + 9)\n")
        XCTAssertEqual(revs.first?.content, "v10\n")
    }

    func testHashIsStableSha256() {
        let h1 = LocalHistoryStore.sha256(of: "hello")
        let h2 = LocalHistoryStore.sha256(of: "hello")
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertNotEqual(h1, LocalHistoryStore.sha256(of: "hello!"))
    }
}
