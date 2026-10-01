import XCTest
@testable import CodeBerry

/// M4: Snapshot Changes — diff manifests, unified patch export.
final class SnapshotChangesTests: XCTestCase {
    func testNoChanges() {
        let base = ["a.swift": "h1", "b.swift": "h2"]
        XCTAssertTrue(SnapshotChanges.compute(base: base, current: base).isEmpty)
    }

    func testAddedModifiedDeleted() {
        let base = ["a.swift": "h1", "b.swift": "h2", "c.swift": "h3"]
        let current = ["a.swift": "h1", "b.swift": "hX", "d.swift": "h4"]
        let changes = SnapshotChanges.compute(base: base, current: current)
        let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0.kind) })
        XCTAssertEqual(byPath["b.swift"], .modified)
        XCTAssertEqual(byPath["c.swift"], .deleted)
        XCTAssertEqual(byPath["d.swift"], .added)
        XCTAssertNil(byPath["a.swift"])
    }

    func testSortedByPath() {
        let changes = SnapshotChanges.compute(base: [:],
                                              current: ["z.swift": "h", "a.swift": "h"])
        XCTAssertEqual(changes.map(\.path), ["a.swift", "z.swift"])
    }

    func testUnifiedDiffModified() {
        let changes = [LocalChange(path: "a.swift", kind: .modified)]
        let diff = SnapshotChanges.unifiedDiff(
            changes: changes,
            readFile: { _ in "let x = 2\nlet y = 3\n" },
            readBase: { _ in "let x = 1\nlet y = 3\n" })
        XCTAssertTrue(diff.contains("--- a/a.swift"))
        XCTAssertTrue(diff.contains("+++ b/a.swift"))
        XCTAssertTrue(diff.contains("-let x = 1"))
        XCTAssertTrue(diff.contains("+let x = 2"))
        XCTAssertTrue(diff.contains(" let y = 3"))
    }

    func testUnifiedDiffAddedAndDeleted() {
        let changes = [LocalChange(path: "n.swift", kind: .added),
                       LocalChange(path: "o.swift", kind: .deleted)]
        let diff = SnapshotChanges.unifiedDiff(
            changes: changes,
            readFile: { $0 == "n.swift" ? "new\n" : nil },
            readBase: { $0 == "o.swift" ? "old\n" : nil })
        XCTAssertTrue(diff.contains("+new"))
        XCTAssertTrue(diff.contains("-old"))
    }

    func testLineDiffEmpty() {
        XCTAssertTrue(SnapshotChanges.unifiedLineDiff(old: ["a"], new: ["a"])
            == [" a"])
    }

    func testLineDiffLargeFileGuard() {
        let big = Array(repeating: "x", count: 600)
        let out = SnapshotChanges.unifiedLineDiff(old: big, new: big.map { $0 + "y" })
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].hasPrefix("# (file too large"))
    }
}
