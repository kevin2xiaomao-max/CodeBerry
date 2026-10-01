import XCTest
@testable import CodeBerry

/// P2 regression: `ArchiveExtractor.sha256(of: URL)` streams the file in
/// 1 MiB chunks instead of `Data(contentsOf:)`-loading the whole file into
/// memory. Output must stay byte-identical to the in-memory hasher.
final class StreamingHashTests: XCTestCase {

    private func tempFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("streaming-hash-\(UUID().uuidString)")
        try contents.write(to: url)
        return url
    }

    /// Small input matches the known SHA-256 vector via both overloads.
    func testStreamingMatchesKnownVector() throws {
        let url = try tempFile(contents: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = ArchiveExtractor.sha256(of: Data("abc".utf8))
        XCTAssertEqual(expected, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try ArchiveExtractor.sha256(of: url), expected)
    }

    /// 5 MiB input (larger than the 1 MiB chunk size) exercises the
    /// multi-chunk incremental path and must equal the one-shot hash.
    func testStreamingLargeFileMatchesOneShot() throws {
        var data = Data()
        data.reserveCapacity(5 * 1024 * 1024)
        for i in 0..<5 { data.append(contentsOf: repeatElement(UInt8(i), count: 1024 * 1024)) }
        let url = try tempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ArchiveExtractor.sha256(of: url),
                       ArchiveExtractor.sha256(of: data))
    }

    /// Empty file hashes to the well-known empty digest.
    func testStreamingEmptyFile() throws {
        let url = try tempFile(contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ArchiveExtractor.sha256(of: url),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// Missing file still surfaces an I/O error (same contract as before).
    func testStreamingMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertThrowsError(try ArchiveExtractor.sha256(of: url))
    }
}
