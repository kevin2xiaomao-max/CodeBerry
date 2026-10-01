import Foundation

// MARK: - 4.0.3 S4 (P0-B): unified symbol resolver
//
// The identifier/type/token/mock lookup layers used to be scattered across
// `evalReference`, `evalMember` and `evalCallInner`. They now live here, in
// one documented order; the evaluator delegates to the resolver and keeps
// behavior otherwise unchanged.
//
// The resolver is pure lookup — invoking computed views/properties is the
// caller's job (it owns source locations for diagnostics).

/// What a bare-identifier lookup found.
enum PreviewResolvedSymbol {
    case value(PreviewValue)
    /// A known cross-file type, safely stubbed (never executed).
    case typeStub(String)
    case computedView(PreviewComputedView)
    case computedProperty(PreviewComputedProperty)
    case unknown
}

/// Thin wrapper over the lookup sources (document, project index, design
/// tokens, mock store). Constructed fresh from the evaluator so it is
/// always in sync — no separate invalidation needed.
struct PreviewResolver {
    var document: PreviewDocument
    var projectIndex: PreviewProjectIndex?
    var mockStore: PreviewMockStore?
    let runtime: PreviewRuntime

    /// All Views visible to an evaluation: project index first, current
    /// document overriding ("当前文件的定义优先").
    var activeViews: [String: PreviewViewStruct] {
        guard let index = projectIndex else { return document.views }
        var merged: [String: PreviewViewStruct] = [:]
        for (name, entry) in index.viewsByName { merged[name] = entry.view }
        for (name, view) in document.views { merged[name] = view }
        return merged
    }

    /// All ordinary types visible: current document first, then the index.
    var activeTypes: [String: PreviewTypeInfo] {
        var merged = projectIndex?.typesByName ?? [:]
        for (name, info) in document.types { merged[name] = info }
        return merged
    }

    /// Resolve a bare identifier in `env`, in layer order:
    /// locals → @State keys → computed subviews → ordinary computed
    /// properties → design tokens → mock store → cross-file types.
    /// `.unknown` when nothing matches — the caller emits the diagnostic.
    func resolve(_ name: String, env: PreviewEvaluator.Env) -> PreviewResolvedSymbol {
        if let local = env.locals[name] { return .value(local) }
        if let key = env.stateKeys[name] { return .value(runtime.value(key) ?? .void) }
        if let view = activeViews[env.typeName] {
            if let computed = view.computedViews[name] { return .computedView(computed) }
            if let prop = view.computedProperties[name] { return .computedProperty(prop) }
        }
        if let token = projectIndex?.tokensByName[name] { return .value(token.value) }
        if let mock = mockStore?.value(for: name) { return .value(mock) }
        if let typeInfo = activeTypes[name] { return .typeStub(typeInfo.name) }
        return .unknown
    }

    /// Resolve `Type.member`: literal static values first, opaque statics
    /// (incl. enum cases) as stubs/members. Nil when the type or member
    /// isn't known — the caller falls through to tokens/mock/unknown.
    func resolveQualified(type typeName: String, member: String) -> PreviewValue? {
        guard let typeInfo = activeTypes[typeName] else { return nil }
        if let value = typeInfo.staticValues[member] { return value }
        if typeInfo.opaqueStatics.contains(member) {
            // Enum cases behave like unqualified members (`.demo`).
            if typeInfo.kind == .enum { return .member(member) }
            return .typeStub(typeInfo.name)
        }
        return nil
    }

    /// Resolve an unknown static function call `Type.foo(...)`: the
    /// implementation is never executed — returns the preview default of
    /// the recorded return type. Nil when the type/function isn't known.
    func resolveStaticCall(type typeName: String, function: String) -> PreviewValue? {
        guard let returnType = activeTypes[typeName]?.staticFunctions[function] else { return nil }
        return PreviewEvaluator.previewDefault(forTypeName: returnType)
    }
}
