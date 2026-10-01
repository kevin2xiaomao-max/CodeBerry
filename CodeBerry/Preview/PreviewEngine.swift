import Foundation
import SwiftParser
import SwiftOperators
import SwiftSyntax

/// Preview failure (§一-6: localized at read time so the message follows the
/// user's language setting). Rendered as an Error banner in the canvas.
struct PreviewError: LocalizedError, Sendable {
    let key: L10nKey
    let params: [String]

    init(_ key: L10nKey, _ params: String...) {
        self.key = key
        self.params = params
    }

    init(key: L10nKey, params: [String] = []) {
        self.key = key
        self.params = params
    }

    var errorDescription: String? {
        let template = L10nService.shared.t(key)
        guard !params.isEmpty else { return template }
        return String(format: template, locale: Locale.current, arguments: params)
    }
}

/// A stored property of a View struct (`@State var count = 0`, `let title: String`).
struct PreviewProperty {
    let name: String
    let isState: Bool
    let initialValue: ExprSyntax?
}

/// A `var xxx: some View { ... }` computed subview inside a View struct.
struct PreviewComputedView {
    let name: String
    let bodyStatements: CodeBlockItemListSyntax?
}

/// One parameter of a `-> some View` helper function.
struct PreviewParameter {
    /// External argument label; nil for `_ name:`.
    let externalLabel: String?
    let localName: String
}

/// A `func xxx(...) -> some View { ... }` helper inside a View struct.
struct PreviewFunction {
    let name: String
    let parameters: [PreviewParameter]
    let bodyStatements: CodeBlockItemListSyntax?
}

/// One `struct Foo: View { ... }` found in the source.
/// A property that needs external data to preview (`@EnvironmentObject`,
/// `@StateObject`, `Repository`/`ViewModel`/… types) — see §七 Mock data.
struct PreviewMockRequirement {
    let propertyName: String
    let typeName: String
}

struct PreviewViewStruct {
    let name: String
    let properties: [PreviewProperty]
    let bodyStatements: CodeBlockItemListSyntax?
    /// Computed subviews (`var xxx: some View`), excluding `body`.
    var computedViews: [String: PreviewComputedView] = [:]
    /// Helper functions returning `some View`.
    var functions: [String: PreviewFunction] = [:]
    /// External dependencies that need Mock data to preview (§七).
    var mockRequirements: [PreviewMockRequirement] = []
}

/// Everything the evaluator needs from one parsed file.
struct PreviewDocument {
    var views: [String: PreviewViewStruct] = [:]
    var viewOrder: [String] = []
    /// Contents of a `#Preview { ... }` block, if present.
    var previewBody: CodeBlockItemListSyntax?
}

/// Parses Swift source into a `PreviewDocument`. Operators are folded
/// (SwiftOperators) so `a + b` arrives as `InfixOperatorExprSyntax` instead of
/// a flat `SequenceExprSyntax`.
struct PreviewEngine {
    let source: String

    /// Parse returning the folded tree + source-location converter, or nil when
    /// the file has syntax errors. The index uses this so one broken file
    /// doesn't poison cross-file lookup.
    func parseTree() -> (file: SourceFileSyntax, converter: SourceLocationConverter)? {
        let raw = Parser.parse(source: source)
        guard !raw.hasError else { return nil }
        let folded = OperatorTable.standardOperators.foldAll(raw) { _ in }
        let file = folded.as(SourceFileSyntax.self) ?? raw
        return (file, SourceLocationConverter(fileName: "", tree: file))
    }

    func parse() throws -> PreviewDocument {
        guard let (file, _) = parseTree() else {
            throw PreviewError(.errPreviewPaused)
        }
        var doc = PreviewDocument()
        Self.collect(into: &doc, from: file)
        guard doc.previewBody != nil || !doc.viewOrder.isEmpty else {
            throw PreviewError(.errNoPreviewableView)
        }
        return doc
    }

    /// Collect top-level Views and #Preview bodies from a parsed tree.
    static func collect(into doc: inout PreviewDocument, from file: SourceFileSyntax) {
        for item in file.statements {
            switch item.item {
            case .decl(let decl):
                if let structDecl = decl.as(StructDeclSyntax.self) {
                    if let view = Self.viewStruct(from: structDecl) {
                        doc.views[view.name] = view
                        doc.viewOrder.append(view.name)
                    }
                } else if let macro = decl.as(MacroExpansionDeclSyntax.self),
                          macro.macroName.text == "Preview" {
                    doc.previewBody = macro.trailingClosure?.statements
                }
            case .expr(let expr):
                if let macro = expr.as(MacroExpansionExprSyntax.self),
                   macro.macroName.text == "Preview" {
                    doc.previewBody = macro.trailingClosure?.statements
                }
            case .stmt:
                break
            }
        }
    }

    // MARK: - Design tokens (§六)

    /// Extract design tokens: top-level `let`s and `static let`s inside any
    /// type. Only literals and pure value expressions (e.g. `Color(...)`)
    /// qualify; anything referencing unknown identifiers is skipped.
    static func extractTokens(file: SourceFileSyntax,
                              fileName: String,
                              converter: SourceLocationConverter) -> [PreviewToken] {
        var tokens: [PreviewToken] = []
        // Throwaway evaluator: token initializers are evaluated with the full
        // expression engine, but diagnostics are discarded.
        let probe = PreviewEvaluator(doc: PreviewDocument(), runtime: PreviewRuntime())
        probe.fileName = fileName
        probe.converter = converter

        func extract(from varDecl: VariableDeclSyntax, prefix: String?) {
            guard varDecl.bindingSpecifier.text == "let",
                  !varDecl.modifiers.contains(where: { $0.name.text == "lazy" }) else { return }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let initializer = binding.initializer?.value else { continue }
                guard let value = try? probe.eval(initializer, env: PreviewEvaluator.Env()),
                      let kind = PreviewToken.Kind(of: value) else { continue }
                let qualified = prefix.map { "\($0).\(name)" } ?? name
                let line = converter.location(for: varDecl.positionAfterSkippingLeadingTrivia).line
                tokens.append(PreviewToken(qualifiedName: qualified,
                                           kind: kind,
                                           value: value,
                                           file: fileName,
                                           line: line,
                                           declStartOffset: varDecl.position.utf8Offset,
                                           declEndOffset: varDecl.endPosition.utf8Offset))
            }
        }

        func isStaticLet(_ varDecl: VariableDeclSyntax) -> Bool {
            varDecl.modifiers.contains { $0.name.text == "static" }
        }

        for item in file.statements {
            guard case .decl(let decl) = item.item else { continue }
            if let varDecl = decl.as(VariableDeclSyntax.self) {
                extract(from: varDecl, prefix: nil)
            } else if let structDecl = decl.as(StructDeclSyntax.self) {
                let typeName = structDecl.name.text
                for member in structDecl.memberBlock.members {
                    if let varDecl = member.decl.as(VariableDeclSyntax.self), isStaticLet(varDecl) {
                        extract(from: varDecl, prefix: typeName)
                    }
                }
            } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
                let typeName = enumDecl.name.text
                for member in enumDecl.memberBlock.members {
                    if let varDecl = member.decl.as(VariableDeclSyntax.self), isStaticLet(varDecl) {
                        extract(from: varDecl, prefix: typeName)
                    }
                }
            }
        }
        return tokens
    }

    private static func viewStruct(from decl: StructDeclSyntax) -> PreviewViewStruct? {
        let conformsToView = decl.inheritanceClause?.inheritedTypes.contains {
            $0.type.trimmedDescription == "View"
        } ?? false
        guard conformsToView else { return nil }

        var properties: [PreviewProperty] = []
        var bodyStatements: CodeBlockItemListSyntax?
        var computedViews: [String: PreviewComputedView] = [:]
        var functions: [String: PreviewFunction] = [:]
        var mockRequirements: [PreviewMockRequirement] = []
        /// Wrapper attributes that mean "this property needs external data".
        let dependencyAttributes = ["EnvironmentObject", "StateObject", "ObservedObject",
                                    "Environment", "Query"]
        /// Type-name fragments that mean the same.
        let dependencyTypes = ["Repository", "Store", "Service", "ViewModel",
                               "Client", "Provider", "Manager"]

        for member in decl.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                if let previewFunction = Self.helperFunction(from: function) {
                    functions[previewFunction.name] = previewFunction
                }
                continue
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isState = variable.attributes.contains { element in
                if case .attribute(let attr) = element {
                    return attr.attributeName.trimmedDescription == "State"
                }
                return false
            }
            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = pattern.identifier.text
                let attrNames: [String] = variable.attributes.compactMap { element in
                    if case .attribute(let attr) = element {
                        return attr.attributeName.trimmedDescription
                    }
                    return nil
                }
                let typeName = binding.typeAnnotation?.type.trimmedDescription ?? ""
                // §七: external dependencies need Mock data to preview.
                if dependencyAttributes.contains(where: attrNames.contains)
                    || dependencyTypes.contains(where: typeName.contains) {
                    mockRequirements.append(PreviewMockRequirement(propertyName: name,
                                                                   typeName: typeName.isEmpty ? "?" : typeName))
                    continue
                }
                if name == "body", let accessorBlock = binding.accessorBlock {
                    switch accessorBlock.accessors {
                    case .getter(let statements):
                        bodyStatements = statements
                    case .accessors(let accessors):
                        for accessor in accessors where accessor.accessorSpecifier.text == "get" {
                            bodyStatements = accessor.body?.statements
                        }
                    }
                } else if binding.typeAnnotation?.type.trimmedDescription.contains("some View") == true,
                          let statements = Self.getterStatements(binding.accessorBlock) {
                    computedViews[name] = PreviewComputedView(name: name, bodyStatements: statements)
                } else if binding.accessorBlock == nil {
                    properties.append(PreviewProperty(name: name,
                                                      isState: isState,
                                                      initialValue: binding.initializer?.value))
                }
            }
        }

        return PreviewViewStruct(name: decl.name.text,
                                 properties: properties,
                                 bodyStatements: bodyStatements,
                                 computedViews: computedViews,
                                 functions: functions,
                                 mockRequirements: mockRequirements)
    }

    /// Returns the getter's statements when the accessor block is a plain
    /// getter (`{ ... }` or accessors containing only `get`), nil otherwise.
    private static func getterStatements(_ accessorBlock: AccessorBlockSyntax?) -> CodeBlockItemListSyntax? {
        guard let accessorBlock else { return nil }
        switch accessorBlock.accessors {
        case .getter(let statements):
            return statements
        case .accessors(let accessors):
            guard accessors.count == 1,
                  accessors.first?.accessorSpecifier.text == "get" else { return nil }
            return accessors.first?.body?.statements
        }
    }

    /// Parses `func xxx(...) -> some View { ... }` (optionally `private`).
    private static func helperFunction(from decl: FunctionDeclSyntax) -> PreviewFunction? {
        let returnsView = decl.signature.returnClause?.type.trimmedDescription.contains("some View") ?? false
        guard returnsView else { return nil }
        let parameters = decl.signature.parameterClause.parameters.map { param in
            PreviewParameter(
                externalLabel: param.firstName.text == "_" ? nil : param.firstName.text,
                localName: param.secondName?.text ?? param.firstName.text
            )
        }
        return PreviewFunction(name: decl.name.text,
                               parameters: parameters,
                               bodyStatements: decl.body?.statements)
    }
}
