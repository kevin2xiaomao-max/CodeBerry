import SwiftUI

// MARK: - §三 Inspector sheet

/// Tap-to-select inspector: adjust params on the selected element, preview
/// the override live, then apply to code with a diff confirmation.
struct PreviewInspectorSheet: View {
    @Bindable var inspector: PreviewInspectorState
    let node: PreviewViewNode
    let source: String
    let filePath: String
    let index: PreviewProjectIndex
    var readFile: ((String) -> String?)?
    var onApply: ([PreviewCanvasView.FileEdit]) -> Void
    var onClose: () -> Void

    @State private var tokenTarget: PreviewToken?
    @State private var tokenDraftName: String?
    @Bindable private var l10n = L10nService.shared

    private var nodeID: String? { node.source?.nodeID }
    private var range: Range<Int>? {
        guard let s = node.source else { return nil }
        return s.startOffset..<s.endOffset
    }
    private var ov: PreviewNodeOverride {
        guard let id = nodeID else { return PreviewNodeOverride() }
        return inspector.overrides[id] ?? PreviewNodeOverride()
    }
    private var params: [PreviewParam] { PreviewInspectorParams.params(for: node) }

    var body: some View {
        NavigationStack {
            Group {
                if let token = tokenTarget {
                    tokenEditView(token)
                } else {
                    paramListView
                }
            }
            .navigationTitle(l10n.t(.inspectorTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.close)) { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.applyToCode)) { applyTapped() }
                        .disabled(!canApply)
                }
            }
        }
    }

    // MARK: Param list

    private var paramListView: some View {
        List {
            if range == nil {
                Text(l10n.t(.unsupported))
                    .foregroundStyle(.secondary)
            }
            ForEach(params, id: \.self) { param in
                paramRow(param)
            }
            if let id = nodeID, inspector.overrides[id] != nil {
                Section {
                    Text(l10n.t(.previewOnlyNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(l10n.t(.reset), role: .destructive) {
                        inspector.clearOverride(for: id)
                    }
                }
            }
            if let s = node.source {
                Section {
                    Text(l10n.t(.fileLine, (s.file as NSString).lastPathComponent, s.line))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func paramRow(_ param: PreviewParam) -> some View {
        switch param {
        case .fontSize:
            doubleRow(param, value: ov.fontSize ?? currentDouble(param),
                      bounds: 8...72, step: 1) { set { $0.fontSize = $1 } }
        case .fontWeight:
            weightRow
        case .textColor:
            colorRow(param, value: ov.textColor ?? currentColor(param),
                     callNames: ["foregroundStyle", "foregroundColor"]) { spec in
                guard let id = nodeID else { return }
                inspector.setOverride({ $0.textColor = spec }, for: id)
            }
        case .lineLimit:
            intRow(param, value: ov.lineLimit ?? currentInt(param),
                   bounds: 1...10, step: 1) { n in
                guard let id = nodeID else { return }
                inspector.setOverride({ $0.lineLimit = n }, for: id)
            }
        case .stackSpacing:
            doubleRow(param, value: ov.stackSpacing ?? currentDouble(param),
                      bounds: 0...64, step: 2) { set { $0.stackSpacing = $1 } }
        case .stackAlignment:
            alignmentRow
        case .padding:
            doubleRow(param, value: ov.padding ?? currentDouble(param),
                      bounds: 0...64, step: 2) { set { $0.padding = $1 } }
        case .width:
            doubleRow(param, value: ov.width ?? currentDouble(param),
                      bounds: 0...800, step: 10) { set { $0.width = $1 } }
        case .height:
            doubleRow(param, value: ov.height ?? currentDouble(param),
                      bounds: 0...800, step: 10) { set { $0.height = $1 } }
        case .minHeight:
            doubleRow(param, value: ov.minHeight ?? currentDouble(param),
                      bounds: 0...800, step: 10) { set { $0.minHeight = $1 } }
        case .maxWidth:
            doubleRow(param, value: ov.maxWidth ?? currentDouble(param),
                      bounds: 0...1200, step: 10) { set { $0.maxWidth = $1 } }
        case .cornerRadius:
            doubleRow(param, value: ov.cornerRadius ?? currentDouble(param),
                      bounds: 0...64, step: 2) { set { $0.cornerRadius = $1 } }
        case .opacity:
            opacityRow
        case .fillColor:
            colorRow(param, value: ov.fillColor ?? currentColor(param),
                     callNames: ["background"]) { spec in
                guard let id = nodeID else { return }
                inspector.setOverride({ $0.fillColor = spec }, for: id)
            }
        case .strokeWidth:
            doubleRow(param, value: ov.strokeWidth ?? currentDouble(param),
                      bounds: 0...20, step: 1) { set { $0.strokeWidth = $1 } }
        }
    }

    private func set(_ mutate: @escaping (inout PreviewNodeOverride, Double) -> Void) -> (Double) -> Void {
        { v in guard let id = nodeID else { return }; inspector.setOverride({ mutate(&$0, v) }, for: id) }
    }

    private func doubleRow(_ param: PreviewParam, value: Double?,
                           bounds: ClosedRange<Double>, step: Double,
                           set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(l10n.t(param.titleKey))
            Spacer()
            Text(value.map { PreviewSourceEditor.fmt($0) } ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper("", value: Binding(get: { value ?? bounds.lowerBound },
                                       set: { set(min(max($0, bounds.lowerBound), bounds.upperBound)) }),
                    in: bounds, step: step)
            .labelsHidden()
        }
        .disabled(range == nil)
    }

    private func intRow(_ param: PreviewParam, value: Int?,
                        bounds: ClosedRange<Int>, step: Int,
                        set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(l10n.t(param.titleKey))
            Spacer()
            Text(value.map(String.init) ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Stepper("", value: Binding(get: { value ?? bounds.lowerBound },
                                       set: { set(min(max($0, bounds.lowerBound), bounds.upperBound)) }),
                    in: bounds, step: step)
            .labelsHidden()
        }
        .disabled(range == nil)
    }

    private var weightRow: some View {
        HStack {
            Text(l10n.t(PreviewParam.fontWeight.titleKey))
            Spacer()
            Picker("", selection: Binding(get: { ov.fontWeight ?? currentWeight() ?? "regular" },
                                          set: { w in guard let id = nodeID else { return }
                                              inspector.setOverride({ $0.fontWeight = w }, for: id) })) {
                ForEach(previewFontWeights, id: \.self) { w in Text(w).tag(w) }
            }
            .pickerStyle(.menu)
        }
        .disabled(range == nil)
    }

    private var alignmentRow: some View {
        HStack {
            Text(l10n.t(PreviewParam.stackAlignment.titleKey))
            Spacer()
            Picker("", selection: Binding(get: { ov.stackAlignment ?? currentAlignment() ?? "center" },
                                          set: { a in guard let id = nodeID else { return }
                                              inspector.setOverride({ $0.stackAlignment = a }, for: id) })) {
                ForEach(["leading", "center", "trailing", "top", "bottom"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.menu)
        }
        .disabled(range == nil)
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l10n.t(PreviewParam.opacity.titleKey))
                Spacer()
                Text(ov.opacity.map { PreviewSourceEditor.fmt($0) } ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { ov.opacity ?? currentDouble(.opacity) ?? 1 },
                                  set: { v in guard let id = nodeID else { return }
                                      inspector.setOverride({ $0.opacity = v }, for: id) }),
                   in: 0...1)
        }
        .disabled(range == nil)
    }

    private func colorRow(_ param: PreviewParam, value: PreviewColorSpec?,
                          callNames: [String],
                          set: @escaping (PreviewColorSpec) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.t(param.titleKey))
                Spacer()
                if let value {
                    Circle().fill(value.toColor()).frame(width: 22, height: 22)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9),
                      spacing: 8) {
                ForEach(PreviewColorSpec.palette, id: \.name) { entry in
                    Button {
                        set(PreviewColorSpec(name: entry.name, red: 0, green: 0, blue: 0, opacity: 1))
                    } label: {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if value?.name == entry.name {
                                    Circle().stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            // §六 token provenance.
            if let token = currentToken(callNames: callNames) {
                tokenBanner(token)
            }
        }
        .disabled(range == nil)
    }

    /// §六: "此值来自设计令牌 X" + 覆盖/改定义二选一.
    private func tokenBanner(_ token: PreviewToken) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(l10n.t(.tokenComesFrom, token.qualifiedName),
                  systemImage: "swatchpalette")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(l10n.t(.tokenEditDefinition)) {
                    tokenTarget = token
                    tokenDraftName = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Token definition editing

    private func tokenEditView(_ token: PreviewToken) -> some View {
        List {
            Section {
                Label(l10n.t(.tokenAffectsMany), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(token.qualifiedName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Section(l10n.t(.paramFillColor)) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9),
                          spacing: 8) {
                    ForEach(PreviewColorSpec.palette, id: \.name) { entry in
                        Button {
                            tokenDraftName = entry.name
                        } label: {
                            Circle()
                                .fill(entry.color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if tokenDraftName == entry.name {
                                        Circle().stroke(Color.accentColor, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button(l10n.t(.cancel), role: .cancel) { tokenTarget = nil }
            }
        }
    }

    // MARK: Current values from source

    private func currentDouble(_ param: PreviewParam) -> Double? {
        guard let range else { return nil }
        let text: String?
        switch param {
        case .fontSize:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["system"], argLabel: "size")
        case .padding:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["padding"])
        case .width: text = frameArg("width", range: range)
        case .height: text = frameArg("height", range: range)
        case .minHeight: text = frameArg("minHeight", range: range)
        case .maxWidth: text = frameArg("maxWidth", range: range)
        case .cornerRadius:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["cornerRadius"])
        case .opacity:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["opacity"])
        case .stackSpacing:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["VStack", "HStack", "ZStack"],
                                                    argLabel: "spacing")
        case .strokeWidth:
            text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["stroke", "strokeBorder"],
                                                    argLabel: "lineWidth")
        default: text = nil
        }
        return text.flatMap(Double.init)
    }

    private func frameArg(_ label: String, range: Range<Int>) -> String? {
        PreviewSourceEditor.argumentText(source: source, range: range,
                                         callNames: ["frame"], argLabel: label)
    }

    private func currentInt(_ param: PreviewParam) -> Int? {
        guard let range else { return nil }
        switch param {
        case .lineLimit:
            return PreviewSourceEditor.argumentText(source: source, range: range,
                                                    callNames: ["lineLimit"])
                .flatMap(Int.init)
        default: return nil
        }
    }

    private func currentWeight() -> String? {
        guard let range else { return nil }
        return PreviewSourceEditor.argumentText(source: source, range: range,
                                                callNames: ["weight"])
            .map { $0.trimmingCharacters(in: .init(charactersIn: ".")) }
    }

    private func currentAlignment() -> String? {
        guard let range else { return nil }
        return PreviewSourceEditor.argumentText(source: source, range: range,
                                                callNames: ["VStack", "HStack", "ZStack"],
                                                argLabel: "alignment")
            .map { $0.trimmingCharacters(in: .init(charactersIn: ".")) }
    }

    private func currentColor(_ param: PreviewParam) -> PreviewColorSpec? {
        guard let range else { return nil }
        let callNames = param == .fillColor ? ["background"] : ["foregroundStyle", "foregroundColor"]
        guard let text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                          callNames: callNames) else { return nil }
        let name = text.trimmingCharacters(in: .init(charactersIn: "."))
        if PreviewColorSpec.palette.contains(where: { $0.name == name }) {
            return PreviewColorSpec(name: name, red: 0, green: 0, blue: 0, opacity: 1)
        }
        return nil
    }

    /// §六 token provenance: does the current argument name a design token?
    private func currentToken(callNames: [String]) -> PreviewToken? {
        guard let range else { return nil }
        guard let text = PreviewSourceEditor.argumentText(source: source, range: range,
                                                          callNames: callNames)?
            .trimmingCharacters(in: .whitespaces) else { return nil }
        return index.tokensByName[text]
    }

    // MARK: Apply

    private var canApply: Bool {
        if tokenTarget != nil { return tokenDraftName != nil }
        guard let id = nodeID, range != nil else { return false }
        return inspector.overrides[id] != nil
    }

    private func applyTapped() {
        if let token = tokenTarget, let name = tokenDraftName {
            // §六: rewrite the token definition itself.
            let tokenSource: String? = token.file == filePath ? source : readFile?(token.file)
            guard let old = tokenSource,
                  let new = PreviewSourceEditor.rewriteToken(
                    source: old, token: token,
                    newValueSource: PreviewColorSpec(name: name, red: 0, green: 0, blue: 0,
                                                     opacity: 1).toSource()),
                  new != old else { return }
            onApply([PreviewCanvasView.FileEdit(path: token.file, oldSource: old, newSource: new)])
            return
        }
        guard let id = nodeID, let range, let o = inspector.overrides[id] else { return }
        var params: [PreviewSourceEditor.ParamEdit] = []
        if let v = o.fontSize { params.append(.editFontSize(v)) }
        if let w = o.fontWeight { params.append(.editFontWeight(w)) }
        if let c = o.textColor { params.append(.editTextColor(c.toSource())) }
        if let n = o.lineLimit { params.append(.editLineLimit(n)) }
        if let v = o.stackSpacing { params.append(.editStackSpacing(v)) }
        if let a = o.stackAlignment { params.append(.editStackAlignment(a)) }
        if let v = o.padding { params.append(.editPadding(v)) }
        if let v = o.width { params.append(.editFrame(label: "width", value: v)) }
        if let v = o.height { params.append(.editFrame(label: "height", value: v)) }
        if let v = o.minHeight { params.append(.editFrame(label: "minHeight", value: v)) }
        if let v = o.maxWidth { params.append(.editFrame(label: "maxWidth", value: v)) }
        if let v = o.cornerRadius { params.append(.editCornerRadius(v)) }
        if let v = o.opacity { params.append(.editOpacity(v)) }
        if let c = o.fillColor { params.append(.editFillColor(c.toSource())) }
        if let v = o.strokeWidth { params.append(.editStrokeWidth(v)) }
        guard let newSource = PreviewSourceEditor.applyParamEdits(params, source: source, range: range),
              newSource != source else { return }
        onApply([PreviewCanvasView.FileEdit(path: filePath, oldSource: source, newSource: newSource)])
    }
}

// MARK: - §十一 Diagnostics sheet

struct PreviewDiagnosticsSheet: View {
    let diagnostics: [PreviewDiagnostic]
    @Binding var errorsOnly: Bool
    @Bindable private var l10n = L10nService.shared
    @Environment(\.dismiss) private var dismiss

    private var visible: [PreviewDiagnostic] {
        errorsOnly ? diagnostics.filter { $0.severity == .error } : diagnostics
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.t(.diagnostics), systemImage: "checkmark.circle")
                    } description: {
                        Text(l10n.t(.noChanges))
                    }
                } else {
                    List(visible) { d in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: d.severity.symbol)
                                .foregroundStyle(color(for: d.severity))
                                .font(.callout)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.message)
                                    .font(.callout)
                                Text(d.locationText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let api = d.api {
                                    Text(api)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(uiColor: .secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(l10n.t(.diagnostics))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.close)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Toggle(l10n.t(.errorsOnly), isOn: $errorsOnly)
                        .toggleStyle(.button)
                }
            }
        }
    }

    private func color(for severity: PreviewDiagnosticSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .ignored: return .gray
        }
    }
}

// MARK: - §七 Mock data sheet

struct PreviewMockSheet: View {
    @Bindable var mockStore: PreviewMockStore
    let requirements: [PreviewMockRequirement]
    var onDone: () -> Void
    @State private var newKey = ""
    @Bindable private var l10n = L10nService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !requirements.isEmpty {
                    Section(l10n.t(.mockNeeded)) {
                        ForEach(requirements, id: \.propertyName) { req in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(req.propertyName).font(.callout.monospaced())
                                    Text(req.typeName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mockStore.value(for: req.propertyName) == nil {
                                    Button(l10n.t(.mockAdd)) {
                                        mockStore.acknowledge(key: req.propertyName)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                Section(l10n.t(.mockData)) {
                    if mockStore.values.isEmpty {
                        Text(l10n.t(.mockEmpty))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mockStore.values.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.callout.monospaced())
                            Spacer()
                            TextField(l10n.t(.mockValue),
                                      text: Binding(get: { mockStore.text(for: key) },
                                                    set: { mockStore.set(key: key, text: $0) }))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .swipeActions {
                            Button(role: .destructive) { mockStore.remove(key: key) } label: {
                                Label(l10n.t(.delete), systemImage: "trash")
                            }
                        }
                    }
                    HStack {
                        TextField(l10n.t(.mockKey), text: $newKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(l10n.t(.mockAdd)) {
                            let key = newKey.trimmingCharacters(in: .whitespaces)
                            guard !key.isEmpty else { return }
                            mockStore.acknowledge(key: key)
                            newKey = ""
                        }
                        .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(l10n.t(.mockData))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.done)) { onDone(); dismiss() }
                }
            }
        }
    }
}

// MARK: - Diff sheets (§三 confirm, §十 before/after)

/// §三: diff confirmation before any inspector write.
struct InspectorDiffSheet: View {
    let edits: [PreviewCanvasView.FileEdit]
    var onConfirm: () -> Void
    var onCancel: () -> Void
    @Bindable private var l10n = L10nService.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(edits) { edit in
                    Section((edit.path as NSString).lastPathComponent) {
                        DiffTextView(diff: PreviewPatch.unifiedDiff(
                            oldText: edit.oldSource,
                            newText: edit.newSource,
                            fileName: (edit.path as NSString).lastPathComponent))
                    }
                }
            }
            .navigationTitle(l10n.t(.confirmApplyTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t(.cancel)) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.confirm)) { onConfirm() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// §十: before/after snapshot diff.
struct SnapshotDiffSheet: View {
    let oldSource: String
    let newSource: String
    let fileName: String
    @Bindable private var l10n = L10nService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let diff = PreviewPatch.unifiedDiff(oldText: oldSource, newText: newSource,
                                                fileName: fileName)
            Group {
                if diff.isEmpty {
                    ContentUnavailableView {
                        Label(l10n.t(.before) + " / " + l10n.t(.after),
                              systemImage: "square.split.1x2")
                    } description: {
                        Text(l10n.t(.noChanges))
                    }
                } else {
                    List {
                        DiffTextView(diff: diff)
                    }
                }
            }
            .navigationTitle(l10n.t(.before) + " / " + l10n.t(.after))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t(.close)) { dismiss() }
                }
            }
        }
    }
}

/// Monospaced diff with +/- coloring.
struct DiffTextView: View {
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.components(separatedBy: "\n").enumerated()),
                    id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(color(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(background(for: line))
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return .primary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.08) }
        return .clear
    }
}
