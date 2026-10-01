import SwiftUI

// MARK: - M3 UI: candidates + readiness + dashboard + mock center

// MARK: Preview candidates (§8) with readiness (§9)

struct PreviewCandidatesView: View {
    let analysis: ProjectAnalysis
    @State private var query = ""
    var onSelect: (PreviewCandidate) -> Void = { _ in }
    var onGenerateFixture: (PreviewCandidate) -> Void = { _ in }
    var onCreateMock: (PreviewCandidate) -> Void = { _ in }
    var onViewDiagnostics: (PreviewCandidate) -> Void = { _ in }

    @Bindable private var l10n = L10nService.shared

    private var candidates: [PreviewCandidate] { analysis.search(query) }

    var body: some View {
        List {
            if candidates.isEmpty {
                Text(l10n.t(.noCandidates))
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { c in
                Button { onSelect(c) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.viewName).font(.headline)
                            Text(c.filePath).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        readinessBadge(for: c)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(l10n.t(.actionGenerateFixture)) { onGenerateFixture(c) }
                        .tint(.blue)
                    Button(l10n.t(.actionCreateMock)) { onCreateMock(c) }
                        .tint(.orange)
                }
            }
        }
        .searchable(text: $query, prompt: l10n.t(.searchCandidates))
        .navigationTitle(l10n.t(.candidatesTitle))
    }

    @ViewBuilder
    private func readinessBadge(for c: PreviewCandidate) -> some View {
        // Readiness is computed on demand per file in the real wiring
        // (WorkspaceStore caches reports); here the badge reflects the
        // candidate kind so the list stays honest without file I/O.
        let (text, color): (String, Color) = switch c.kind {
        case .macroPreview, .previewProvider:
            (l10n.t(.readinessReady), .green)
        case .pageView:
            (l10n.t(.readinessReady), .green)
        case .featureView, .component:
            (l10n.t(.readinessNeedsMock), .yellow)
        }
        Text(text).font(.caption).foregroundStyle(color)
    }
}

// MARK: Readiness banner (§9)

struct PreviewReadinessBanner: View {
    let report: PreviewReadiness.Report
    var onAction: (PreviewReadiness.Action) -> Void = { _ in }
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        if !report.isReady {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusIcon
                    Text(statusText).font(.headline)
                }
                ForEach(report.secondary.indices, id: \.self) { i in
                    Text(detailText(for: report.secondary[i]))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    ForEach(report.actions, id: \.self) { action in
                        Button(actionText(for: action)) { onAction(action) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch report.primary {
        case .ready: return Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsMock: return Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .missingComponentSupport: return Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .externalPackageNotExecuted: return Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .syntaxError: return Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unsupportedRuntime: return Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var statusText: String {
        switch report.primary {
        case .ready: return l10n.t(.readinessReady)
        case .needsMock(let r): return l10n.t(.readinessNeedsMock) + "：" + r.joined(separator: "、")
        case .missingComponentSupport(let c): return l10n.t(.readinessMissingComponent) + "：" + c.joined(separator: "、")
        case .externalPackageNotExecuted(let p): return l10n.t(.readinessExternalPackage) + "：" + p.joined(separator: "、")
        case .syntaxError: return l10n.t(.readinessSyntaxError)
        case .unsupportedRuntime(let d): return l10n.t(.readinessUnsupportedRuntime) + "：" + d.joined(separator: "、")
        }
    }

    private func detailText(for status: PreviewReadiness.Status) -> String {
        switch status {
        case .ready: return l10n.t(.readinessReady)
        case .needsMock(let r): return l10n.t(.readinessNeedsMock) + "：" + r.joined(separator: "、")
        case .missingComponentSupport(let c): return l10n.t(.readinessMissingComponent) + "：" + c.joined(separator: "、")
        case .externalPackageNotExecuted(let p): return l10n.t(.readinessExternalPackage) + "：" + p.joined(separator: "、")
        case .syntaxError(let d): return l10n.t(.readinessSyntaxError) + "：" + d
        case .unsupportedRuntime(let d): return l10n.t(.readinessUnsupportedRuntime) + "：" + d.joined(separator: "、")
        }
    }

    private func actionText(for action: PreviewReadiness.Action) -> String {
        switch action {
        case .generateFixture: return l10n.t(.actionGenerateFixture)
        case .createMock: return l10n.t(.actionCreateMock)
        case .ignoreNonVisual: return l10n.t(.actionIgnoreNonVisual)
        case .viewDiagnostics: return l10n.t(.actionViewDiagnostics)
        }
    }
}

// MARK: Compatibility dashboard (§24)

struct CompatibilityDashboardView: View {
    @Bindable private var l10n = L10nService.shared
    private var items: [ComponentEntry] { ComponentRegistry.dashboardItems() }

    var body: some View {
        List {
            ForEach(ComponentSupportLevel.allCases, id: \.self) { level in
                Section(levelTitle(for: level)) {
                    ForEach(items.filter { $0.supportLevel == level }, id: \.symbol) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.symbol).font(.headline)
                                Spacer()
                                Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            if !item.diagnostics.isEmpty {
                                Text(item.diagnostics).font(.caption).foregroundStyle(.secondary)
                            }
                            if !item.acceptedArgs.isEmpty {
                                Text(item.acceptedArgs.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let w = item.workaround {
                                Text(" workaround：" + w).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(l10n.t(.dashboardTitle))
    }

    private func levelTitle(for level: ComponentSupportLevel) -> String {
        switch level {
        case .supported: return "✅ " + l10n.t(.levelSupported)
        case .approximate: return "🟡 " + l10n.t(.levelApproximate)
        case .cosmeticIgnore: return "⚪️ " + l10n.t(.levelCosmeticIgnore)
        case .unsupported: return "🔴 " + l10n.t(.levelUnsupported)
        }
    }
}

// MARK: Mock Center (§17)

struct MockCenterView: View {
    @Bindable var center: MockCenter
    @Bindable private var l10n = L10nService.shared
    @State private var newProfileName = ""
    @State private var showingAdd = false

    var body: some View {
        Form {
            Section(l10n.t(.profile)) {
                Picker(l10n.t(.profile), selection: profileBinding) {
                    ForEach(center.profiles) { p in
                        Text(p.displayName).tag(p.id as String?)
                    }
                }
                Toggle(l10n.t(.dark), isOn: darkBinding)
            }
            if let profile = center.activeProfile {
                Section(l10n.t(.mockValues)) {
                    ForEach(profile.values.keys.sorted(), id: \.self) { key in
                        mockRow(key: key, value: profile.values[key]!)
                    }
                }
            }
            Section {
                Button(l10n.t(.addProfile)) { showingAdd = true }
                if center.profiles.count > 1, let id = center.activeProfileID {
                    Button(l10n.t(.delete), role: .destructive) {
                        center.removeProfile(id: id)
                    }
                }
            }
        }
        .navigationTitle(l10n.t(.mockCenterTitle))
        .alert(l10n.t(.addProfile), isPresented: $showingAdd) {
            TextField(l10n.t(.profileName), text: $newProfileName)
            Button(l10n.t(.ok)) {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { center.addProfile(named: name) }
                newProfileName = ""
            }
            Button(l10n.t(.cancel), role: .cancel) { newProfileName = "" }
        }
    }

    private var profileBinding: Binding<String?> {
        Binding(get: { center.activeProfileID },
                set: { center.activeProfileID = $0 })
    }

    private var darkBinding: Binding<Bool> {
        Binding(get: { center.activeProfile?.darkMode ?? false },
                set: { v in
                    guard let id = center.activeProfileID,
                          let idx = center.profiles.firstIndex(where: { $0.id == id }) else { return }
                    center.profiles[idx].darkMode = v
                })
    }

    @ViewBuilder
    private func mockRow(key: String, value: MockValue) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(key).font(.caption)
                Text(value.kindLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if value.kind == .bool {
                Toggle("", isOn: boolBinding(key: key, value: value))
                    .labelsHidden()
            } else {
                TextField(value.kindLabel, text: textBinding(key: key, value: value))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func textBinding(key: String, value: MockValue) -> Binding<String> {
        Binding(get: { value.text },
                set: { center.setQualifiedValue(MockValue(kind: value.kind, text: $0), forKey: key) })
    }

    private func boolBinding(key: String, value: MockValue) -> Binding<Bool> {
        Binding(get: { value.text == "true" },
                set: { center.setQualifiedValue(.bool($0), forKey: key) })
    }
}

private extension MockValue {
    var kindLabel: String {
        switch kind {
        case .string: return "String"
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .color: return "Color"
        case .date: return "Date"
        case .customStruct: return "Struct"
        case .array: return "Array"
        }
    }
}
