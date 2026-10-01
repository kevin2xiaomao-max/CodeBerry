import XCTest
import ZIPFoundation
@testable import CodeBerry

/// §三十九: ArchiveSecurity — zip slip / traversal / symlink / 炸弹包防护.
final class ArchiveSecurityTests: XCTestCase {

    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a zip at `tmp/name` with the given (path → data) entries.
    /// `type` applies to all entries (use `.symlink` for link entries whose
    /// data is the link target).
    private func makeZip(_ name: String,
                         entries: [(path: String, data: Data)],
                         type: Entry.EntryType = .file) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        guard let archive = try? Archive(url: url, accessMode: .create) else {
            throw ArchiveExtractor.ExtractError.unreadableArchive
        }
        for (path, data) in entries {
            // Provider contract: return exactly the requested slice.
            try archive.addEntry(with: path, type: type,
                                 uncompressedSize: UInt32(data.count),
                                 provider: { position, size in
                                     data.subdata(in: position..<position + size)
                                 })
        }
        return url
    }

    private func extractDir(_ name: String) -> URL {
        let url = tmp.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Happy path

    func testValidZipExtracts() throws {
        let zip = try makeZip("valid.zip", entries: [
            ("repo-abc123/README.md", Data("hello".utf8)),
            ("repo-abc123/Sources/main.swift", Data("print(1)".utf8)),
        ])
        let dest = extractDir("out-valid")
        let files = try ArchiveExtractor.extractSecurely(zipURL: zip, to: dest)
        // Top-level prefix stripped.
        XCTAssertEqual(Set(files.map(\.relativePath)),
                       ["README.md", "Sources/main.swift"])
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("README.md")),
                       "hello")
    }

    func testMacOSXAndDSStoreSkipped() throws {
        let zip = try makeZip("hygiene.zip", entries: [
            ("repo-x/__MACOSX/._README", Data("junk".utf8)),
            ("repo-x/.DS_Store", Data("junk".utf8)),
            ("repo-x/ok.txt", Data("ok".utf8)),
        ])
        let dest = extractDir("out-hygiene")
        let files = try ArchiveExtractor.extractSecurely(zipURL: zip, to: dest)
        XCTAssertEqual(files.map(\.relativePath), ["ok.txt"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("__MACOSX").path))
    }

    // MARK: - Attacks

    func testPathTraversalRejected() throws {
        let zip = try makeZip("traversal.zip", entries: [
            ("repo-x/../../evil.txt", Data("pwn".utf8)),
        ])
        XCTAssertThrowsError(
            try ArchiveExtractor.extractSecurely(zipURL: zip, to: extractDir("out-trav"))) { error in
            guard case ArchiveExtractor.ExtractError.pathTraversal = error else {
                return XCTFail("expected pathTraversal, got \(error)")
            }
        }
        // Nothing escaped the sandbox.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("evil.txt").path))
    }

    func testAbsolutePathRejected() throws {
        let zip = try makeZip("absolute.zip", entries: [
            ("/tmp/absolute-evil.txt", Data("pwn".utf8)),
        ])
        XCTAssertThrowsError(
            try ArchiveExtractor.extractSecurely(zipURL: zip, to: extractDir("out-abs"))) { error in
            guard case ArchiveExtractor.ExtractError.absolutePath = error else {
                return XCTFail("expected absolutePath, got \(error)")
            }
        }
    }

    func testSymlinkRejected() throws {
        let zip = try makeZip("symlink.zip",
                              entries: [("repo-x/link", Data("/etc/passwd".utf8))],
                              type: .symlink)
        XCTAssertThrowsError(
            try ArchiveExtractor.extractSecurely(zipURL: zip, to: extractDir("out-link"))) { error in
            guard case ArchiveExtractor.ExtractError.symlinkRejected = error else {
                return XCTFail("expected symlinkRejected, got \(error)")
            }
        }
    }

    func testEntryCountCap() throws {
        // Build the count cheaply: the cap is checked before extraction,
        // so small entries are fine.
        var entries: [(String, Data)] = []
        for i in 0..<(ArchiveExtractor.maxEntries + 1) {
            entries.append(("f\(i).txt", Data("x".utf8)))
        }
        let zip = try makeZip("many.zip", entries: entries)
        XCTAssertThrowsError(
            try ArchiveExtractor.extractSecurely(zipURL: zip, to: extractDir("out-many"))) { error in
            guard case ArchiveExtractor.ExtractError.tooManyEntries = error else {
                return XCTFail("expected tooManyEntries, got \(error)")
            }
        }
    }

    func testCorruptZipRejected() throws {
        let url = tmp.appendingPathComponent("corrupt.zip")
        try Data("not a zip at all".utf8).write(to: url)
        XCTAssertThrowsError(
            try ArchiveExtractor.extractSecurely(zipURL: url, to: extractDir("out-corrupt"))) { error in
            guard case ArchiveExtractor.ExtractError.unreadableArchive = error else {
                return XCTFail("expected unreadableArchive, got \(error)")
            }
        }
    }

    // MARK: - Prefix detection

    func testCommonPrefixDetection() throws {
        let zip = try makeZip("prefix.zip", entries: [
            ("owner-repo-sha/a.txt", Data("a".utf8)),
            ("owner-repo-sha/b/c.txt", Data("c".utf8)),
        ])
        let archive = try Archive(url: zip, accessMode: .read)
        XCTAssertEqual(ArchiveExtractor.commonTopLevelPrefix(of: Array(archive)),
                       "owner-repo-sha/")
    }

    func testNoPrefixWhenFlat() throws {
        let zip = try makeZip("flat.zip", entries: [
            ("a.txt", Data("a".utf8)),
            ("b.txt", Data("b".utf8)),
        ])
        let archive = try Archive(url: zip, accessMode: .read)
        XCTAssertNil(ArchiveExtractor.commonTopLevelPrefix(of: Array(archive)))
    }

    func testSHA256() {
        XCTAssertEqual(ArchiveExtractor.sha256(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
