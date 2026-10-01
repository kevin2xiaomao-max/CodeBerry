import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - M3 §8 ProjectAnalyzer
//
// After a GitHub import the workspace must not show "just a file tree".
// The analyzer scans the repo (background-friendly, cancellable, capped)
// and produces a ranked list of previewable pages plus project metadata:
//
//  1. views with #Preview
//  2. page-level Views
//  3. feature Views
//  4. components
//
// It also collects design tokens (TypeName.member), ViewModifiers, Shapes
// and custom View symbols — the raw material for the Inspector 4.0
// token-awareness and the Component Registry.

/// A view that can be previewed.
struct PreviewCandidate: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        case macroPreview      // has #Preview
        case previewProvider   // conforms to PreviewProvider
        case pageView          // name/path contains Page|Screen
        case featureView       // under Features/
        case component         // everything else
    }

    let filePath: String   // project-root-relative (prepend currentProject for workspace paths)
    let viewName: String
    let kind: Kind
    let hasSyntaxError: Bool

    var id: String { filePath + "#" + viewName }

    /// §8 ranking: 1. #Preview 2. page 3. feature 4. component.
    var rank: Int {
        switch kind {
        case .macroPreview, .previewProvider: return 0
        case .pageView: return 1
        case .featureView: return 2
        case .component: return 3
        }
    }
}

/// A design token reference: `V32Layout.sectionGap`.
struct DesignToken: Hashable, Sendable {
    let typeName: String
    let memberName: String
    let filePath: String
    var reference: String { "\(typeName).\(memberName)" }
}

enum ProjectKind: String, Sendable {
    case xcodeproj, xcworkspace, packageSwift, unknown
}

struct ProjectAnalysis: Sendable {
    let rootPath: String
    let projectKind: ProjectKind
    let candidates: [PreviewCandidate]   // already ranked
    let tokens: [DesignToken]
    let customViews: [String]
    let viewModifiers: [String]
    let shapes: [String]
    let fileCount: Int
    let truncated: Bool                  // hit the scan cap

    /// §8: supports search.
    func search(_ query: String) -> [PreviewCandidate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.viewName.localizedCaseInsensitiveContains(q)
                || $0.filePath.localizedCaseInsensitiveContains(q)
        }
    }
}

/// Scans a repo directory. Pure value type; the caller decides the thread.
/// `isCancelled` is polled between files so background indexing stays
/// cancellable (§26). Never throws — one broken file never poisons the rest.
struct ProjectAnalyzer {
    /// 4.0.2 P0-1: file cap unified via `ProjectIndexPolicy` (was a private
    /// 1000 that disagreed with the preview index's 100).
    static var maxFiles: Int { ProjectIndexPolicy.maxFiles }
    private static let skipDirNames: Set<String> = [
        ".git", ".build", "Pods", "DerivedData", ".swiftpm",
        "Carthage", "node_modules", "fastlane",
    ]
    /// Heuristic: type names that usually hold design tokens.
    private static let tokenTypeSuffixes = ["Tokens", "Token", "Layout", "Colors", "Typography", "Spacing", "Radius", "Shadows"]

    static func analyze(root: URL, isCancelled: @escaping @Sendable () -> Bool = { false }) -> ProjectAnalysis {
        let fm = FileManager.default
        var kind: ProjectKind = .unknown
        var swiftFiles: [URL] = []
        var relPaths: [String] = []
        let rootPath = root.path

        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if isCancelled() { break }
                let name = url.lastPathComponent
                if skipDirNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathExtension == "xcodeproj" { kind = .xcodeproj }
                else if url.pathExtension == "xcworkspace" { kind = .xcworkspace }
                else if name == "Package.swift" && kind == .unknown { kind = .packageSwift }
                if url.pathExtension == "swift" {
                    swiftFiles.append(url)
                    relPaths.append(relativePath(of: url, rootPath: rootPath))
                }
                if swiftFiles.count >= maxFiles { break }
            }
        }
        let truncated = swiftFiles.count >= maxFiles

        var candidates: [PreviewCandidate] = []
        var tokens: [DesignToken] = []
        var views = Set<String>()
        var modifiers = Set<String>()
        var shapes = Set<String>()

        for (url, rel) in zip(swiftFiles, relPaths) {
            if isCancelled() { break }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let tree = Parser.parse(source: text)
            let collector = DeclCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            let hasError = tree.hasError

            // 4.0.3 S10 (P0-H): Page Discovery only lists production
            // views — a generated fixture is never a second production view.
            let role = PreviewSourceRole.classify(path: rel, content: text)
            let isPreviewableFile = role.isPreviewablePage

            for viewName in collector.viewStructs {
                views.insert(viewName)
                guard isPreviewableFile else { continue }
                let k: PreviewCandidate.Kind
                if collector.previewProviders.contains(viewName) { k = .previewProvider }
                else if viewName.hasSuffix("Page") || viewName.hasSuffix("Screen")
                            || rel.contains("Page") || rel.contains("Screen") { k = .pageView }
                else if rel.contains("Features/") { k = .featureView }
                else { k = .component }
                candidates.append(PreviewCandidate(filePath: rel, viewName: viewName,
                                                   kind: k, hasSyntaxError: hasError))
            }
            // PreviewProvider structs that don't inherit View (the common
            // `struct X_Previews: PreviewProvider` pattern) are candidates too.
            guard isPreviewableFile else { continue }
            for providerName in collector.previewProviders where !views.contains(providerName) {
                views.insert(providerName)
                candidates.append(PreviewCandidate(filePath: rel, viewName: providerName,
                                                   kind: .previewProvider, hasSyntaxError: hasError))
            }
            if collector.hasPreviewMacro {
                // A #Preview macro at file scope — rank first. Prefer upgrading
                // a view struct from this file; otherwise add a file-level entry.
                let idxs = candidates.indices.filter { candidates[$0].filePath == rel }
                if let first = idxs.first {
                    candidates[first] = PreviewCandidate(filePath: rel,
                                                         viewName: candidates[first].viewName,
                                                         kind: .macroPreview, hasSyntaxError: hasError)
                } else {
                    let name = (rel as NSString).deletingPathExtension
                        .components(separatedBy: "/").last ?? rel
                    candidates.append(PreviewCandidate(filePath: rel, viewName: name,
                                                       kind: .macroPreview, hasSyntaxError: hasError))
                }
            }
            for m in collector.viewModifiers { modifiers.insert(m) }
            for s in collector.shapes { shapes.insert(s) }
            for t in collector.tokens {
                tokens.append(DesignToken(typeName: t.typeName, memberName: t.member,
                                          filePath: rel))
            }
        }

        candidates.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.viewName != $1.viewName { return $0.viewName < $1.viewName }
            return $0.filePath < $1.filePath
        }

        return ProjectAnalysis(rootPath: rootPath, projectKind: kind,
                               candidates: candidates, tokens: tokens,
                               customViews: views.sorted(), viewModifiers: modifiers.sorted(),
                               shapes: shapes.sorted(), fileCount: swiftFiles.count,
                               truncated: truncated)
    }

    private static func relativePath(of url: URL, rootPath: String) -> String {
        let p = url.path
        if p.hasPrefix(rootPath + "/") { return String(p.dropFirst(rootPath.count + 1)) }
        return url.lastPathComponent
    }

    // MARK: - Syntax collection

    private final class DeclCollector: SyntaxVisitor {
        var viewStructs: [String] = []
        var previewProviders: Set<String> = []
        var viewModifiers: [String] = []
        var shapes: [String] = []
        var tokens: [(typeName: String, member: String)] = []
        var hasPreviewMacro = false

        override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
            if node.macroName.text == "Preview" { hasPreviewMacro = true }
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let inherited = (node.inheritanceClause?.inheritedTypes ?? []).map {
                $0.type.trimmedDescription
            }
            let inherits: (String) -> Bool = { want in
                inherited.contains { $0 == want || $0.hasPrefix(want + "<") }
            }
            if inherits("View") {
                viewStructs.append(name)
                if inherits("PreviewProvider") { previewProviders.insert(name) }
            } else if inherits("PreviewProvider") {
                previewProviders.insert(name)
            }
            if inherits("ViewModifier") { viewModifiers.append(name) }
            if inherits("Shape") { shapes.append(name) }
            // Design tokens: `enum V32Layout { static let sectionGap = 16 }`.
            if ProjectAnalyzer.tokenTypeSuffixes.contains(where: { name.hasSuffix($0) })
                || name.hasPrefix("V32") || name.hasPrefix("DS") {
                for member in node.memberBlock.members {
                    if let varDecl = member.decl.as(VariableDeclSyntax.self),
                       varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                        for binding in varDecl.bindings {
                            if let id = binding.pattern.as(IdentifierPatternSyntax.self) {
                                tokens.append((name, id.identifier.text))
                            }
                        }
                    }
                }
            }
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            if ProjectAnalyzer.tokenTypeSuffixes.contains(where: { name.hasSuffix($0) })
                || name.hasPrefix("V32") || name.hasPrefix("DS") {
                for member in node.memberBlock.members {
                    if let varDecl = member.decl.as(VariableDeclSyntax.self),
                       varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                        for binding in varDecl.bindings {
                            if let id = binding.pattern.as(IdentifierPatternSyntax.self) {
                                tokens.append((name, id.identifier.text))
                            }
                        }
                    }
                }
            }
            return .visitChildren
        }
    }
}
