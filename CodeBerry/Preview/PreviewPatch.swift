import Foundation
import SwiftUI
import UIKit

/// §九 Patch export: unified diffs and `.patch` files. Export only —
/// nothing is ever pushed automatically (spec §十四).
enum PreviewPatch {
    /// Line-based unified diff (LCS), standard `---`/`+++`/`@@` format.
    static func unifiedDiff(oldText: String, newText: String, fileName: String) -> String {
        let a = oldText.components(separatedBy: "\n")
        let b = newText.components(separatedBy: "\n")
        if a == b { return "" }
        let hunks = diffHunks(a: a, b: b)
        var out = ["--- a/\(fileName)", "+++ b/\(fileName)"]
        for hunk in hunks {
            out.append("@@ -\(hunk.aStart + 1),\(hunk.aCount) +\(hunk.bStart + 1),\(hunk.bCount) @@")
            for line in hunk.lines { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private struct Hunk {
        var aStart: Int; var aCount: Int
        var bStart: Int; var bCount: Int
        var lines: [String] = []
    }

    /// Myers-free LCS diff grouped into hunks with 3 lines of context.
    private static func diffHunks(a: [String], b: [String]) -> [Hunk] {
        let n = a.count, m = b.count
        // LCS table. Files here are editor-sized; fine.
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        // Walk the edit script.
        enum Op { case same(String), del(String), ins(String) }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                ops.append(.same(a[i])); i += 1; j += 1
            } else if j < m, (i >= n || dp[i][j + 1] >= dp[i + 1][j]) {
                ops.append(.ins(b[j])); j += 1
            } else if i < n {
                ops.append(.del(a[i])); i += 1
            }
        }
        // Group into hunks with `context` lines around each change run.
        let context = 3
        var spans: [(Int, Int)] = []
        var hStart: Int? = nil
        var pendingSame = 0
        for k in 0..<ops.count {
            let isSame: Bool = { if case .same = ops[k] { return true }; return false }()
            if isSame {
                if hStart != nil {
                    pendingSame += 1
                    if pendingSame > context {
                        spans.append((hStart!, k - pendingSame + context))
                        hStart = nil
                        pendingSame = 0
                    }
                }
            } else {
                if hStart == nil { hStart = max(0, k - context) }
                pendingSame = 0
            }
        }
        if let hs = hStart { spans.append((hs, ops.count)) }
        // Merge overlapping spans.
        var merged: [(Int, Int)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, span.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, span.1))
            } else {
                merged.append(span)
            }
        }
        // Emit hunks.
        var hunks: [Hunk] = []
        for (s, e) in merged {
            var ta = 0, tb = 0
            for k in 0..<s {
                switch ops[k] {
                case .same: ta += 1; tb += 1
                case .del: ta += 1
                case .ins: tb += 1
                }
            }
            var hunk = Hunk(aStart: ta, aCount: 0, bStart: tb, bCount: 0)
            for k in s..<e {
                switch ops[k] {
                case .same(let str):
                    hunk.lines.append(" " + str); hunk.aCount += 1; hunk.bCount += 1
                case .del(let str):
                    hunk.lines.append("-" + str); hunk.aCount += 1
                case .ins(let str):
                    hunk.lines.append("+" + str); hunk.bCount += 1
                }
            }
            hunks.append(hunk)
        }
        return hunks
    }

    /// Write the diff to a temp `.patch` file for the share sheet.
    static func patchFileURL(diff: String, fileName: String) -> URL? {
        let base = (fileName as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base).patch")
        do {
            try diff.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// UIKit share sheet wrapper.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
