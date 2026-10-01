import Foundation
import CryptoKit
import ZIPFoundation

/// Secure zip extraction for GitHub zipballs (§8: zip 安全解压).
///
/// Guards (each covered by `ArchiveSecurityTests`):
/// - **zip slip / traversal**: entries with absolute paths or `..` segments
///   that would escape the destination are rejected.
/// - **symlinks**: rejected outright — a symlink could point outside the
///   sandbox and `FileManager` follows them implicitly.
/// - **zip bombs**: hard caps on total uncompressed bytes and entry count.
/// - **hygiene**: `__MACOSX/` resource forks and `.DS_Store` files are skipped.
enum ArchiveExtractor {
    /// Refuse archives claiming more than 500MB uncompressed.
    static let maxUncompressedBytes: Int64 = 500_000_000
    /// Refuse archives with more than 50k entries.
    static let maxEntries = 50_000

    struct ExtractedFile {
        let relativePath: String
        let size: Int64
    }

    enum ExtractError: Error, LocalizedError {
        case unreadableArchive
        case tooManyEntries(Int)
        case archiveTooLarge(Int64)
        case symlinkRejected(String)
        case pathTraversal(String)
        case absolutePath(String)

        var errorDescription: String? {
            switch self {
            case .unreadableArchive: return L10nService.shared.t(.errArchiveUnreadable)
            case .tooManyEntries(let n): return L10nService.shared.t(.errArchiveTooManyEntries, String(n))
            case .archiveTooLarge(let b): return L10nService.shared.t(.errArchiveTooLarge, ByteCountFormatter.string(fromByteCount: b, countStyle: .file))
            case .symlinkRejected(let p): return L10nService.shared.t(.errArchiveSymlink, p)
            case .pathTraversal(let p): return L10nService.shared.t(.errArchiveTraversal, p)
            case .absolutePath(let p): return L10nService.shared.t(.errArchiveAbsolutePath, p)
            }
        }
    }

    /// Extracts `zipURL` into `destination` (created if needed).
    /// GitHub zipballs wrap everything in one top-level directory
    /// (`<owner>-<repo>-<sha>/`); that prefix is stripped so the workspace
    /// gets a clean layout. Returns the extracted file list (dirs excluded).
    static func extractSecurely(zipURL: URL, to destination: URL,
                                progress: ((Double) -> Void)? = nil) throws -> [ExtractedFile] {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ExtractError.unreadableArchive
        }
        let entries = Array(archive)
        guard entries.count <= maxEntries else { throw ExtractError.tooManyEntries(entries.count) }
        let totalBytes = entries.reduce(Int64(0)) { $0 + Int64($1.uncompressedSize) }
        guard totalBytes <= maxUncompressedBytes else { throw ExtractError.archiveTooLarge(totalBytes) }

        let prefix = commonTopLevelPrefix(of: entries)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let destPath = destination.standardized.path
        var extracted: [ExtractedFile] = []
        for (i, entry) in entries.enumerated() {
            progress?(Double(i) / Double(max(entries.count, 1)))
            // Absolute paths are rejected on the raw entry path, before the
            // common-prefix strip (a "/" prefix would otherwise be stripped
            // away and the check below would never fire).
            if entry.path.hasPrefix("/") { throw ExtractError.absolutePath(entry.path) }
            var rel = entry.path
            if let prefix, rel.hasPrefix(prefix) { rel = String(rel.dropFirst(prefix.count)) }
            // Hygiene: skip macOS resource forks and Finder metadata.
            if rel.hasPrefix("__MACOSX/") || rel.hasSuffix(".DS_Store") { continue }
            if rel.isEmpty || rel == "/" { continue }

            if entry.type == .symlink { throw ExtractError.symlinkRejected(entry.path) }
            if rel.hasPrefix("/") { throw ExtractError.absolutePath(entry.path) }

            let target = destination.appendingPathComponent(rel).standardized
            let targetPath = target.path
            guard targetPath == destPath || targetPath.hasPrefix(destPath + "/") else {
                throw ExtractError.pathTraversal(entry.path)
            }
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: target)
            extracted.append(ExtractedFile(relativePath: rel, size: Int64(entry.uncompressedSize)))
        }
        progress?(1)
        return extracted
    }

    /// The single top-level directory shared by every entry (GitHub's
    /// `<owner>-<repo>-<sha>/`), or nil when entries are already flat.
    static func commonTopLevelPrefix(of entries: [Entry]) -> String? {
        let paths = entries.map(\.path).filter { !$0.isEmpty }
        guard let first = paths.first else { return nil }
        guard let slash = first.firstIndex(of: "/") else { return nil }
        let candidate = String(first[...slash])   // includes trailing "/"
        guard paths.allSatisfy({ $0.hasPrefix(candidate) }) else { return nil }
        // Don't strip when the archive is a single file at top level.
        guard paths.count > 1 || first != candidate else { return nil }
        return candidate
    }

    /// Streaming SHA-256 hex of a file's contents — the manifest fingerprint.
    /// P2 hotfix: reads 1 MiB chunks through a FileHandle into an incremental
    /// CryptoKit hasher, so multi-hundred-MB archives never load fully into
    /// memory. Byte-identical output to `sha256(of: Data)`. Throws on I/O
    /// errors like the previous `Data(contentsOf:)` implementation did.
    static func sha256(of url: URL) throws -> String {
        let chunkSize = 1024 * 1024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 hex of in-memory data (for tests).
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
