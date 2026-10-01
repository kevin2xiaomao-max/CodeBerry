import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - M3 §9 Preview Readiness
//
// A page that can't be previewed must not "just throw an error".
// Readiness reports a precise status plus the actions that unblock it:
//
//   ✅ ready                  — direct preview
//   🟡 needsMock              — e.g. HomeRepository requires a Mock
//   🟡 missingComponentSupport — custom view the evaluator doesn't know
//   🟡 externalPackageNotExecuted — Charts etc. never execute
//   🔴 syntaxError
//   🔴 unsupportedRuntime     — e.g. SwiftData runtime unavailable

struct PreviewReadiness: Sendable {
    enum Status: Sendable, Equatable {
        case ready
        case needsMock(reasons: [String])
        case missingComponentSupport(components: [String])
        case externalPackageNotExecuted(packages: [String])
        case syntaxError(details: String)
        case unsupportedRuntime(dependencies: [String])
    }

    /// Actions the UI offers for a non-ready page (§9).
    enum Action: Sendable, Hashable, CaseIterable {
        case generateFixture   // 生成 Preview Fixture
        case createMock        // 创建 Mock
        case ignoreNonVisual   // 忽略非视觉依赖
        case viewDiagnostics   // 查看 Diagnostics
    }

    struct Report: Sendable {
        /// The dominant status shown in the banner.
        let primary: Status
        /// Everything else that was found (shown in the detail list).
        let secondary: [Status]
        let actions: [Action]
        var isReady: Bool {
            if case .ready = primary { return true }
            return false
        }
    }

    /// Analyze one file's source for the named view.
    static func report(of viewName: String, in source: String,
                      knownViews: Set<String> = []) -> Report {
        let tree = Parser.parse(source: source)
        if tree.hasError {
            return Report(primary: .syntaxError(details: firstErrorLine(in: tree) ?? ""),
                          secondary: [],
                          actions: [.viewDiagnostics])
        }

        var secondary: [Status] = []
        var primary: Status = .ready

        // 🔴 Unsupported runtime: SwiftData / @Model / @Query.
        var runtimeDeps: [String] = []
        if source.contains("import SwiftData") || source.contains("@Model")
            || source.contains("@Query") || source.contains("SwiftData.") {
            runtimeDeps.append("SwiftData")
        }
        if !runtimeDeps.isEmpty {
            primary = .unsupportedRuntime(dependencies: runtimeDeps)
        }

        // 🟡 Needs Mock: Repository / ViewModel / Service / Client properties,
        //    @EnvironmentObject / @StateObject.
        var mockReasons: [String] = []
        let finder = MemberFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        for (prop, type) in finder.properties where isDataDependency(type) {
            mockReasons.append("\(prop): \(type)")
        }
        if finder.hasEnvironmentObject { mockReasons.append("@EnvironmentObject") }
        if finder.hasStateObject { mockReasons.append("@StateObject") }
        if !mockReasons.isEmpty {
            let s = Status.needsMock(reasons: mockReasons)
            if case .ready = primary { primary = s } else { secondary.append(s) }
        }

        // 🟡 Missing component support: custom views the evaluator can't build.
        let used = finder.viewFactoryNames
        let unknown = used.filter {
            !ComponentRegistry.isKnownView($0) && !knownViews.contains($0)
                && $0.first?.isUppercase == true
                && !Self.nonViewCallNames.contains($0)
        }
        if !unknown.isEmpty {
            let s = Status.missingComponentSupport(components: Array(Set(unknown)).sorted())
            if case .ready = primary { primary = s } else { secondary.append(s) }
        }

        // 🟡 External packages never execute.
        var packages: [String] = []
        for pkg in ["Charts", "MapKit", "WebKit", "AVKit"] {
            if source.contains("import \(pkg)") { packages.append(pkg) }
        }
        if !packages.isEmpty {
            let s = Status.externalPackageNotExecuted(packages: packages)
            if case .ready = primary { primary = s } else { secondary.append(s) }
        }

        var actions: [Action] = []
        switch primary {
        case .ready: break
        case .needsMock: actions = [.createMock, .generateFixture, .viewDiagnostics]
        case .missingComponentSupport: actions = [.viewDiagnostics, .generateFixture]
        case .externalPackageNotExecuted: actions = [.ignoreNonVisual, .viewDiagnostics]
        case .syntaxError: actions = [.viewDiagnostics]
        case .unsupportedRuntime: actions = [.createMock, .generateFixture, .viewDiagnostics]
        }
        return Report(primary: primary, secondary: secondary, actions: actions)
    }

    private static func isDataDependency(_ type: String) -> Bool {
        let t = type.trimmingCharacters(in: .whitespaces)
        for kw in ["Repository", "ViewModel", "Service", "Client", "Store", "DataSource", "Provider", "Manager"] {
            if t.contains(kw) { return true }
        }
        return false
    }

    // MARK: - 4.0.2 P0-4: never components
    //
    /// Call names that are never SwiftUI view components: Swift standard
    /// library, Foundation, and SwiftUI non-view value types that appear as
    /// calls in view code. The old filter (uppercase first letter only)
    /// misreported them as "missing custom component support", which pushed
    /// perfectly previewable pages into 🟡.
    private static let nonViewCallNames: Set<String> = [
        // Swift standard library
        "Array", "Dictionary", "Set", "String", "Substring", "Character",
        "Int", "Double", "Float", "CGFloat", "Bool", "Optional", "Result",
        // Foundation
        "Date", "DateComponents", "DateInterval", "Locale", "Calendar",
        "TimeZone", "DateFormatter", "NumberFormatter", "URL", "URLComponents",
        "UUID", "Data", "JSONDecoder", "JSONEncoder", "UserDefaults",
        "NotificationCenter", "Timer", "Decimal", "Measurement", "IndexPath",
        "NSRange", "NSString", "NSArray", "NSDictionary", "NSNumber",
        "NSStringFromString", "NSLocalizedString",
        // SwiftUI / Combine non-view value types commonly called in view code
        "Binding", "StrokeStyle", "Animation", "Transaction", "ColorScheme",
        "EditMode", "AnyTransition",
    ]

    private static func firstErrorLine(in tree: SourceFileSyntax) -> String? {
        // Best-effort: return the first ~80 chars around the first token with
        // an error presence. Keep it cheap — diagnostics UI shows details.
        for token in tree.tokens(viewMode: .sourceAccurate) {
            if token.presence == .missing { return token.text }
        }
        return nil
    }

    // MARK: - Syntax walk

    private final class MemberFinder: SyntaxVisitor {
        var properties: [(name: String, type: String)] = []
        var hasEnvironmentObject = false
        var hasStateObject = false
        var viewFactoryNames = Set<String>()
        private var insideViewStruct = false

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            let was = insideViewStruct
            let inherits = (node.inheritanceClause?.inheritedTypes ?? []).map { $0.type.trimmedDescription }
            if inherits.contains("View") { insideViewStruct = true }
            defer { insideViewStruct = was }
            return .visitChildren
        }

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            let attrs = node.attributes.map { $0.trimmedDescription }
            if attrs.contains(where: { $0.contains("EnvironmentObject") }) { hasEnvironmentObject = true }
            if attrs.contains(where: { $0.contains("StateObject") }) { hasStateObject = true }
            for binding in node.bindings {
                guard let id = binding.pattern.as(IdentifierPatternSyntax.self),
                      let anno = binding.typeAnnotation else { continue }
                properties.append((id.identifier.text, anno.type.trimmedDescription))
            }
            return .visitChildren
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let name = calledName(of: node) { viewFactoryNames.insert(name) }
            return .visitChildren
        }

        private func calledName(of call: FunctionCallExprSyntax) -> String? {
            if let decl = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return decl.baseName.text
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                return member.declName.baseName.text
            }
            return nil
        }
    }
}
