import Foundation
import SwiftSyntax

/// §三 Source location attached to every rendered node, so the Inspector can
/// tap-to-select an element and map an override back to the exact code range.
struct PreviewSourceInfo: Hashable {
    /// Workspace-relative file path.
    let file: String
    /// 1-based line number.
    let line: Int
    /// UTF-8 offset range of the expression that produced the node.
    let startOffset: Int
    let endOffset: Int

    /// Stable identity for selection: file + start offset.
    var nodeID: String { "\(file)@\(startOffset)" }
}
