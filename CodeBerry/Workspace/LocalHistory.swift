import CryptoKit
import Foundation

// MARK: - M4: Local History
//
// Every successful file save records a revision. Users can browse the
// revision list per file and restore any earlier version. Bounded:
// max 50 revisions per file, entries older than 30 days are pruned.

/// One saved revision of a file.
struct LocalHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    /// Workspace-relative path.
    let path: String
    let date: Date
    /// SHA-256 of content (dedupe: identical saves don't create revisions).
    let contentHash: String
    let content: String
    /// File size at save time, for display.
    let byteCount: Int

    init(path: String, date: Date = Date(), content: String) {
        self.id = UUID()
        self.path = path
        self.date = date
        self.content = content
        self.contentHash = LocalHistoryStore.sha256(of: content)
        self.byteCount = content.utf8.count
    }
}

/// Persistent, bounded per-file revision history.
/// Local file history. All mutations are serialized on a private queue;
/// immutable after init otherwise. Safe to share.
final class LocalHistoryStore: @unchecked Sendable {
    static let maxRevisionsPerFile = 50
    static let maxAgeDays = 30

    private let directory: URL
    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "codeberry.localhistory", qos: .utility)

    /// Production store under Application Support.
    static let shared = LocalHistoryStore()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("CodeBerry/LocalHistory", isDirectory: true)
        }
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: - Recording

    /// Records a revision after a successful save. No-op when the content
    /// is identical to the latest recorded revision.
    func record(path: String, content: String) {
        queue.async { [weak self] in
            self?.recordSync(path: path, content: content)
        }
    }

    /// Synchronous variant for tests.
    func recordSync(path: String, content: String) {
        var entries = loadEntries(for: path)
        let hash = Self.sha256(of: content)
        if entries.last?.contentHash == hash { return }  // unchanged
        entries.append(LocalHistoryEntry(path: path, content: content))
        entries = Array(entries.suffix(Self.maxRevisionsPerFile))
        saveEntries(entries, for: path)
    }

    // MARK: - Reading

    /// Revisions for a file, newest last.
    func revisions(for path: String) -> [LocalHistoryEntry] {
        queue.sync { loadEntries(for: path) }
    }

    /// Prunes entries older than `maxAgeDays`. Called on launch.
    func pruneOldEntries() {
        queue.async { [weak self] in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-Double(Self.maxAgeDays) * 86400)
            for file in (try? fm.contentsOfDirectory(at: directory,
                                                     includingPropertiesForKeys: nil)) ?? [] {
                var entries = loadEntriesFile(file)
                let kept = entries.filter { $0.date >= cutoff }
                if kept.count != entries.count {
                    if kept.isEmpty {
                        try? fm.removeItem(at: file)
                    } else {
                        entries = kept
                        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
                    }
                }
            }
        }
    }

    // MARK: - Storage

    private func fileURL(for path: String) -> URL {
        // Flatten the path into a safe filename.
        let safe = path.replacingOccurrences(of: "/", with: "__")
                        .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent(safe + ".json")
    }

    private func loadEntries(for path: String) -> [LocalHistoryEntry] {
        loadEntriesFile(fileURL(for: path))
    }

    private func loadEntriesFile(_ url: URL) -> [LocalHistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LocalHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries(_ entries: [LocalHistoryEntry], for path: String) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    // MARK: - Hashing

    static func sha256(of string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
