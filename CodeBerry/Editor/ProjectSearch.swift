import Foundation

/// One hit of a project-wide text search.
struct ProjectSearchResult: Identifiable, Hashable {
    let id = UUID()
    /// Project-relative path.
    let filePath: String
    /// 1-based.
    let line: Int
    let lineText: String

    static func == (lhs: ProjectSearchResult, rhs: ProjectSearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Full-text search across the project (pure Swift, no subprocess).
/// Skips hidden directories, binary files, and caps results so the UI stays
/// responsive on large imports.
enum ProjectSearch {
    static let maxResults = 300
    static let maxFileBytes = 2 * 1024 * 1024

    static func search(projectRoot: URL, query: String,
                       caseSensitive: Bool = false,
                       fileExtension: String? = nil) -> [ProjectSearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [ProjectSearchResult] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let needle = caseSensitive ? query : query.lowercased()
        for case let url as URL in enumerator {
            if results.count >= maxResults { break }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if let ext = fileExtension, url.pathExtension != ext { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maxFileBytes { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if content.utf8.prefix(1024).contains(0) { continue }  // binary
            let relative = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            let ns = content as NSString
            var lineNumber = 1
            var searchStart = 0
            while searchStart < ns.length, results.count < maxResults {
                let lineRange = ns.lineRange(for: NSRange(location: searchStart, length: 0))
                let lineText = ns.substring(with: lineRange)
                let comparable = caseSensitive ? lineText : lineText.lowercased()
                if comparable.contains(needle) {
                    results.append(ProjectSearchResult(
                        filePath: relative,
                        line: lineNumber,
                        lineText: String(lineText.trimmingCharacters(in: .newlines).prefix(200))))
                }
                lineNumber += 1
                let next = NSMaxRange(lineRange)
                if next <= searchStart { break }
                searchStart = next
            }
        }
        return results
    }
}
