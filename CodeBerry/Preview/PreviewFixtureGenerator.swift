import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - 4.0.2 P0-7: preview-only SwiftData-bypassing fixture wrapper
//
// The old "fixture" was a verbatim source snapshot: opening it in Xcode
// Previews ran the view against the REAL SwiftData store (or failed without
// a container). This generator instead emits a preview-only WRAPPER
// (`<View>PreviewFixture`) that truly bypasses SwiftData:
//
//   - Production logic / schema / Repository are never modified — the
//     generator only READS the view's source (it returns a String).
//   - The wrapper injects an IN-MEMORY ModelContainer built from the `@Query`
//     element types discovered in the source: no real DB writes, ever.
//   - The wrapper performs no network I/O.
//
// The CodeBerry canvas itself never executes SwiftData at all (P0-6 mocks);
// this wrapper targets Xcode `#Preview`.
//
// 4.0.3 S12 (P0-J): the SINGLE fixture pipeline — every fixture entry
// point goes through `pipelinePlan → validate → generate → register`.
// The old `header + original source → write file` fallback branch in the
// UI is deleted; a snapshot is now an explicit plan kind.
// `plan(for:in:)` keeps its 4.0.2 contract (nil when no SwiftData) for the
// existing tests.

struct PreviewFixtureGenerator {
    struct FixturePlan: Sendable {
        /// e.g. "HomeViewPreviewFixture"
        let wrapperName: String
        /// The wrapped view, e.g. "HomeView"
        let viewName: String
        /// `@Query` element types discovered in the view's source.
        let modelTypes: [String]
        /// Full file source of `<View>PreviewFixture.swift`.
        let source: String
    }

    /// 4.0.2 contract (kept): SwiftData wrapper plan, or nil when the
    /// source doesn't define the view, has syntax errors, or the view
    /// doesn't use SwiftData (no wrapper needed).
    static func plan(for viewName: String, in source: String) -> FixturePlan? {
        guard let a = analyze(viewName: viewName, in: source), a.usesSwiftData else { return nil }
        return FixturePlan(wrapperName: "\(viewName)PreviewFixture",
                           viewName: viewName,
                           modelTypes: a.modelTypes,
                           source: swiftDataWrapperSource(viewName: viewName,
                                                          wrapperName: "\(viewName)PreviewFixture",
                                                          modelTypes: a.modelTypes))
    }

    // MARK: - S12 single pipeline: plan → validate → generate → register

    enum PipelineKind: Sendable {
        /// SwiftData-bypassing wrapper with an in-memory container.
        case swiftDataWrapper(modelTypes: [String])
        /// Verbatim source snapshot (the view uses no SwiftData).
        case snapshot
    }

    struct PipelinePlan: Sendable {
        let kind: PipelineKind
        /// e.g. "HomeViewPreviewFixture" (wrapper) or "HomeViewFixture" (snapshot).
        let wrapperName: String
        let viewName: String
        /// e.g. "HomeViewPreviewFixture.swift".
        var fileName: String { wrapperName + ".swift" }
    }

    /// Unified plan: nil only when the source has syntax errors or doesn't
    /// define the view. A non-SwiftData view gets an explicit snapshot plan
    /// (never a nil that the UI branches on).
    static func pipelinePlan(for viewName: String, in source: String) -> PipelinePlan? {
        guard let a = analyze(viewName: viewName, in: source) else { return nil }
        if a.usesSwiftData {
            return PipelinePlan(kind: .swiftDataWrapper(modelTypes: a.modelTypes),
                                wrapperName: "\(viewName)PreviewFixture",
                                viewName: viewName)
        }
        return PipelinePlan(kind: .snapshot,
                            wrapperName: "\(viewName)Fixture",
                            viewName: viewName)
    }

    /// The plan is sound: names are non-empty and the generated source
    /// re-parses without syntax errors.
    static func validate(_ plan: PipelinePlan, source: String) -> Bool {
        guard !plan.viewName.isEmpty, !plan.wrapperName.isEmpty else { return false }
        return !Parser.parse(source: generate(plan, from: source)).hasError
    }

    /// Produce the fixture file source for a validated plan.
    static func generate(_ plan: PipelinePlan, from source: String) -> String {
        switch plan.kind {
        case .swiftDataWrapper(let modelTypes):
            return swiftDataWrapperSource(viewName: plan.viewName,
                                          wrapperName: plan.wrapperName,
                                          modelTypes: modelTypes)
        case .snapshot:
            return snapshotSource(plan: plan, source: source)
        }
    }

    /// Write the fixture file and record it in the registry (which bumps
    /// the cache fingerprint's fixture revision). Returns the written
    /// project-relative path, or nil when the write failed.
    @discardableResult
    static func register(_ plan: PipelinePlan,
                         source: String,
                         project: String,
                         registry: PreviewFixtureRegistry,
                         writeFile: (String, String) -> Bool) -> String? {
        let fixtureSource = generate(plan, from: source)
        let path = "\(project)/PreviewFixtures/\(plan.fileName)"
        guard writeFile(path, fixtureSource) else { return nil }
        registry.register(name: plan.wrapperName, source: fixtureSource)
        return path
    }

    // MARK: - Analysis (shared)

    private static func analyze(viewName: String, in source: String)
    -> (usesSwiftData: Bool, modelTypes: [String])? {
        let tree = Parser.parse(source: source)
        guard !tree.hasError else { return nil }
        let finder = QueryFinder(viewName: viewName)
        finder.walk(tree)
        guard finder.foundView else { return nil }
        return (finder.usesSwiftData, finder.modelTypes)
    }

    // MARK: - Source templates

    private static func swiftDataWrapperSource(viewName: String,
                                               wrapperName: String,
                                               modelTypes: [String]) -> String {
        let containerArgs = modelTypes.isEmpty
            ? "for: []"
            : "for: [\(modelTypes.map { "\($0).self" }.joined(separator: ", "))]"
        let modelNote = modelTypes.isEmpty
            ? "\n// No @Query models were discovered in \(viewName); add your @Model\n// types to the `for:` list below if the preview needs them."
            : ""

        return """
        // \(wrapperName).swift
        // Preview-only fixture — generated by CodeBerry 4.0.3 (single pipeline).
        //
        // SwiftData is truly bypassed: the wrapper injects an IN-MEMORY
        // container, so Xcode Previews never touch the real database and no
        // network calls are made. Production logic, schema, and Repository
        // code are untouched — this file only references \(viewName).
        // DO NOT SHIP — preview only.
        \(modelNote)
        import SwiftUI
        import SwiftData

        /// Preview-only wrapper for `\(viewName)`.
        struct \(wrapperName): View {
            var body: some View {
                \(viewName)()
                    .modelContainer(\(containerArgs), inMemory: true)
            }
        }

        #Preview("\(viewName) — Fixture (in-memory SwiftData)") {
            \(wrapperName)()
        }
        """
    }

    private static func snapshotSource(plan: PipelinePlan, source: String) -> String {
        """
        // \(plan.fileName)
        // Preview Fixture — generated by CodeBerry 4.0.3 (single pipeline).
        // Source view: \(plan.viewName)
        // Kind: snapshot (verbatim source copy; the view uses no SwiftData).

        \(source)
        """
    }

    // MARK: - Syntax walk

    private final class QueryFinder: SyntaxVisitor {
        let viewName: String
        var foundView = false
        var usesSwiftData = false
        var modelTypes: [String] = []
        private var insideTargetView = false
        // 4.0.2: a stack, not a defer — SyntaxVisitor visits children
        // AFTER visit() returns, so `defer { insideTargetView = was }`
        // would reset the flag before the @Query vars are ever seen
        // (that bug silently produced modelTypes == []).
        private var viewStack: [Bool] = []

        init(viewName: String) {
            self.viewName = viewName
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
            if node.path.map(\.name.text).joined(separator: ".") == "SwiftData" {
                usesSwiftData = true
            }
            return .skipChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let inherits = (node.inheritanceClause?.inheritedTypes ?? []).map { $0.type.trimmedDescription }
            let isTarget = node.name.text == viewName && inherits.contains("View")
            if isTarget { foundView = true }
            viewStack.append(isTarget)
            insideTargetView = viewStack.contains(true)
            return .visitChildren
        }

        override func visitPost(_ node: StructDeclSyntax) {
            if !viewStack.isEmpty { viewStack.removeLast() }
            insideTargetView = viewStack.contains(true)
        }

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            let isQuery = node.attributes.contains { element in
                if case .attribute(let attr) = element {
                    return attr.attributeName.trimmedDescription == "Query"
                }
                return false
            }
            if isQuery {
                usesSwiftData = true
                if insideTargetView {
                    for binding in node.bindings {
                        let typeDesc = binding.typeAnnotation?.type.trimmedDescription ?? ""
                        if let element = MockCenter.arrayElementType(of: typeDesc),
                           !modelTypes.contains(element) {
                            modelTypes.append(element)
                        }
                    }
                }
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text
            if name == "modelContext" || name == "ModelContext" || name == "ModelContainer" {
                usesSwiftData = true
            }
            return .skipChildren
        }
    }
}
