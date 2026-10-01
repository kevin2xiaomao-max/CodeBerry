import Foundation
import SwiftParser
import SwiftSyntax

/// A named declaration found in a Swift source file.
struct CodeSymbol: Hashable, Identifiable {
    enum Kind: String, CaseIterable {
        case `class`, `struct`, `enum`, `protocol`, `extension`
        case function, initializer, variable, constant, `typealias`, enumCase

        var iconName: String {
            switch self {
            case .class: return "c.square"
            case .struct: return "s.square"
            case .enum: return "e.square"
            case .protocol: return "p.square"
            case .extension: return "e.square.fill"
            case .function: return "f.square"
            case .initializer: return "i.square"
            case .variable: return "v.square"
            case .constant: return "l.square"
            case .typealias: return "t.square"
            case .enumCase: return "list.bullet"
            }
        }

        var localizedName: String {
            switch self {
            case .class: return "类"
            case .struct: return "结构体"
            case .enum: return "枚举"
            case .protocol: return "协议"
            case .extension: return "扩展"
            case .function: return "函数"
            case .initializer: return "构造器"
            case .variable: return "变量"
            case .constant: return "常量"
            case .typealias: return "类型别名"
            case .enumCase: return "枚举值"
            }
        }
    }

    let id = UUID()
    let name: String
    let kind: Kind
    /// Project-relative path, e.g. "Sources/Home/HomeView.swift".
    let filePath: String
    /// 1-based line / column of the identifier.
    let line: Int
    let column: Int
    let parentName: String?

    static func == (lhs: CodeSymbol, rhs: CodeSymbol) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Project-wide index of Swift declarations, built with SwiftSyntax.
/// Per-file content hashes make re-indexing incremental: unchanged files are
/// skipped.
final class SymbolIndex {
    private(set) var symbols: [CodeSymbol] = []
    private var fingerprints: [String: Int] = [:]
    private var symbolsByFile: [String: [CodeSymbol]] = [:]

    var isEmpty: Bool { symbols.isEmpty }

    /// Full rebuild over every .swift file under `projectRoot`.
    func rebuild(projectRoot: URL) {
        symbols = []
        fingerprints = [:]
        symbolsByFile = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let relative = url.path.replacingOccurrences(
                of: projectRoot.path + "/", with: "")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            indexFile(relativePath: relative, content: content)
        }
    }

    /// Incremental update for a single file (called on save / text change).
    func updateFile(relativePath: String, content: String) {
        indexFile(relativePath: relativePath, content: content)
    }

    func removeFile(relativePath: String) {
        fingerprints.removeValue(forKey: relativePath)
        symbolsByFile.removeValue(forKey: relativePath)
        symbols.removeAll { $0.filePath == relativePath }
    }

    // MARK: - Queries

    /// Fuzzy (subsequence) match on symbol names, best matches first.
    func symbols(matching query: String, limit: Int = 50) -> [CodeSymbol] {
        guard !query.isEmpty else { return Array(symbols.prefix(limit)) }
        return symbols
            .compactMap { sym -> (CodeSymbol, Int)? in
                guard let score = fuzzyScore(query: query, in: sym.name) else { return nil }
                return (sym, score)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func symbols(inFile relativePath: String) -> [CodeSymbol] {
        symbolsByFile[relativePath] ?? []
    }

    /// Jump to Definition: exact name match, preferring the same file.
    func definition(of name: String, inFile relativePath: String? = nil) -> CodeSymbol? {
        let candidates = symbols.filter { $0.name == name }
        if let file = relativePath,
           let sameFile = candidates.first(where: { $0.filePath == file }) {
            return sameFile
        }
        // Prefer types/functions over variables when ambiguous.
        return candidates.sorted {
            Self.kindPriority($0.kind) < Self.kindPriority($1.kind)
        }.first
    }

    /// Find References: naive whole-word scan, excluding the definition site.
    /// `fileContents` maps relative path → current text.
    func references(of symbol: CodeSymbol,
                   fileContents: [String: String]) -> [ReferenceHit] {
        var hits: [ReferenceHit] = []
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: symbol.name) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for (path, content) in fileContents {
            let ns = content as NSString
            var lineNumber = 1
            // Walk line by line so we can report 1-based line numbers.
            var searchStart = 0
            while searchStart < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: searchStart, length: 0))
                let lineText = ns.substring(with: lineRange)
                let lineNS = lineText as NSString
                let matches = regex.matches(in: lineText,
                                            range: NSRange(location: 0, length: lineNS.length))
                if !matches.isEmpty {
                    let isDefSite = (path == symbol.filePath && lineNumber == symbol.line)
                    if !isDefSite { hits.append(ReferenceHit(filePath: path, line: lineNumber)) }
                }
                lineNumber += 1
                searchStart = NSMaxRange(lineRange)
            }
        }
        return hits.sorted { $0.line < $1.line }
    }

    // MARK: - Private

    private func indexFile(relativePath: String, content: String) {
        let fingerprint = content.hashValue
        if fingerprints[relativePath] == fingerprint { return }  // unchanged
        fingerprints[relativePath] = fingerprint
        symbols.removeAll { $0.filePath == relativePath }

        let tree = Parser.parse(source: content)
        let converter = SourceLocationConverter(fileName: relativePath, tree: tree)
        let collector = SymbolCollector(filePath: relativePath, converter: converter)
        collector.walk(tree)

        symbolsByFile[relativePath] = collector.symbols
        symbols.append(contentsOf: collector.symbols)
    }

    private static func kindPriority(_ kind: CodeSymbol.Kind) -> Int {
        switch kind {
        case .class, .struct, .enum, .protocol: return 0
        case .function, .initializer: return 1
        case .typealias, .enumCase: return 2
        case .extension: return 3
        case .variable, .constant: return 4
        }
    }
}

/// Subsequence fuzzy match. Lower score = better (earlier + tighter matches).
/// Shared by SymbolIndex and Quick Open; defined in QuickOpenView.swift.


// MARK: - Syntax walk

private final class SymbolCollector: SyntaxVisitor {
    var symbols: [CodeSymbol] = []
    private let filePath: String
    private let converter: SourceLocationConverter
    private var typeStack: [String] = []

    init(filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func record(name: String, kind: CodeSymbol.Kind, node: some SyntaxProtocol) {
        let pos = node.positionAfterSkippingLeadingTrivia
        let loc = converter.location(for: pos)
        symbols.append(CodeSymbol(name: name, kind: kind, filePath: filePath,
                                  line: loc.line, column: loc.column,
                                  parentName: typeStack.last))
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .class, node: node.name)
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .struct, node: node.name)
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .enum, node: node.name)
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .protocol, node: node.name)
        typeStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.extendedType.trimmedDescription, kind: .extension,
               node: node.extensionKeyword)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .function, node: node.name)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: "init", kind: .initializer, node: node.initKeyword)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let kind: CodeSymbol.Kind = node.bindingSpecifier.text == "let" ? .constant : .variable
        for binding in node.bindings {
            if let ident = binding.pattern.as(IdentifierPatternSyntax.self) {
                record(name: ident.identifier.text, kind: kind, node: ident.identifier)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .typealias, node: node.name)
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            record(name: element.name.text, kind: .enumCase, node: element.name)
        }
        return .visitChildren
    }
}
