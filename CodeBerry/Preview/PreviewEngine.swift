import Foundation
import SwiftParser
import SwiftOperators
import SwiftSyntax

struct PreviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A stored property of a View struct (`@State var count = 0`, `let title: String`).
struct PreviewProperty {
    let name: String
    let isState: Bool
    let initialValue: ExprSyntax?
}

/// One `struct Foo: View { ... }` found in the source.
struct PreviewViewStruct {
    let name: String
    let properties: [PreviewProperty]
    let bodyStatements: CodeBlockItemListSyntax?
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

    func parse() throws -> PreviewDocument {
        let raw = Parser.parse(source: source)
        guard !raw.hasError else {
            throw PreviewError(message: "Preview paused — the file has syntax errors.")
        }
        let folded = OperatorTable.standardOperators.foldAll(raw) { _ in }
        let file = folded.as(SourceFileSyntax.self) ?? raw

        var doc = PreviewDocument()
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

        guard doc.previewBody != nil || !doc.viewOrder.isEmpty else {
            throw PreviewError(message: "Nothing to preview — add a struct conforming to View or a #Preview block.")
        }
        return doc
    }

    private static func viewStruct(from decl: StructDeclSyntax) -> PreviewViewStruct? {
        let conformsToView = decl.inheritanceClause?.inheritedTypes.contains {
            $0.type.trimmedDescription == "View"
        } ?? false
        guard conformsToView else { return nil }

        var properties: [PreviewProperty] = []
        var bodyStatements: CodeBlockItemListSyntax?

        for member in decl.memberBlock.members {
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
                if name == "body", let accessorBlock = binding.accessorBlock {
                    switch accessorBlock.accessors {
                    case .getter(let statements):
                        bodyStatements = statements
                    case .accessors(let accessors):
                        for accessor in accessors where accessor.accessorSpecifier.text == "get" {
                            bodyStatements = accessor.body?.statements
                        }
                    }
                } else if binding.accessorBlock == nil {
                    properties.append(PreviewProperty(name: name,
                                                      isState: isState,
                                                      initialValue: binding.initializer?.value))
                }
            }
        }

        return PreviewViewStruct(name: decl.name.text,
                                 properties: properties,
                                 bodyStatements: bodyStatements)
    }
}
