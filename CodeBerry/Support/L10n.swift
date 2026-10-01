import Foundation
import Observation

/// App display language: follow system, Simplified Chinese, or English.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

/// Centralized localization keys (§一-7: no scattered literals).
/// Every user-facing string lives in `L10nService.table`.
enum L10nKey: String, CaseIterable {
    // MARK: §一-5 required UI strings
    case projects
    case newProject
    case newFile
    case preview
    case files
    case editor
    case settings
    case appearance
    case language
    case device
    case light
    case dark
    case system
    case inspector
    case apply
    case reset
    case exportPatch
    case copyCode
    case warnings
    case previewError
    case unsupported
    case reload
    case save
    case cancel
    case create

    // MARK: §一-6 error messages
    case errSyntaxError        // 无法预览：当前文件存在语法错误
    case errUnsupportedAPI     // 暂不支持此 SwiftUI API: %@
    case errComponentNotFound  // 找不到组件 %@
    case errPreviewPaused      // 预览已暂停
    case errNoPreviewableView  // 无法预览：请添加遵循 View 的 struct 或 #Preview
    case errNoBody             // %@ 没有可预览的 body
    case errRecursionDeep      // 视图嵌套过深（可能是递归视图）

    // MARK: App chrome
    case appName
    case done
    case close
    case confirm
    case delete
    case rename
    case ok

    // MARK: Settings
    case settingsWorkspace
    case settingsLocation
    case settingsLocationDesc
    case settingsAbout
    case settingsVersion
    case settingsAboutDesc
    case languageFollowSystem
    case languageZhHans
    case languageEnglish

    // MARK: Projects
    case noProjects
    case noProjectsDesc
    case createAppProject
    case createEmptyProject
    case newProjectMessage
    case projectNamePlaceholder
    case renameProject
    case newNamePlaceholder
    case deleteProjectMessage
    case folderKind
    case iosAppKind

    // MARK: File navigator
    case newFolder
    case newFolderMessage      // 创建于%@。
    case workspaceRoot
    case renameFile
    case deleteFileMessage
    case backToProjects
    case navigatorEmptyDesc

    // MARK: Editor
    case noFileOpen
    case noFileOpenDesc

    // MARK: Canvas toolbar
    case indexing              // 正在建立预览索引…
    case diagnostics
    case errorsOnly
    case showIgnored
    case severityError
    case severityWarning
    case severityIgnored
    case orientation
    case portrait
    case landscape
    case safeArea
    case deviceIPhoneAir
    case deviceIPhonePro
    case deviceIPhoneProMax
    case deviceCompactIPhone
    case deviceIPad
    case followSystem
    case snapshot
    case more

    // MARK: Inspector
    case tapToInspect          // 轻点画布中的元素进行调整
    case inspectorTitle
    case paramFontSize
    case paramFontWeight
    case paramTextColor
    case paramLineLimit
    case paramSpacing
    case paramAlignment
    case paramPadding
    case paramWidth
    case paramHeight
    case paramMinHeight
    case paramMaxWidth
    case paramCornerRadius
    case paramOpacity
    case paramFillColor
    case paramStrokeWidth
    case applyToCode
    case previewOnlyNote      // 仅在预览中生效，不修改源码
    case showDiff
    case confirmApplyTitle    // 确认应用到代码
    case writeFailed          // 写入失败，原文件未改动
    case tokenComesFrom       // 此值来自设计令牌 %@
    case tokenOverrideOnly    // 仅本次预览覆盖
    case tokenEditDefinition  // 修改令牌定义
    case tokenAffectsMany     // 此修改可能影响多个页面
    case noSelection

    // MARK: Mock data
    case mockData
    case mockNeeded           // 此依赖需要 Mock 才能预览
    case mockAdd
    case mockKey
    case mockValue
    case mockEmpty

    // MARK: Fixture generation
    case generateFixture
    case fixtureGenerated     // 已生成 %@

    // MARK: Patch export
    case viewDiff
    case copyPatch
    case exportPatchFile
    case copyModifiedCode
    case diffTitle
    case noChanges

    // MARK: Before / After
    case before
    case after
    case saveSnapshot
    case snapshotSaved

    // MARK: Diagnostics (§十一)
    case diagDeclInBody
    case diagExprNotView
    case diagIfLet
    case diagExprUnsupported
    case diagNotState
    case diagUnknownIdentifier
    case diagMemberUnsupported
    case diagOperatorUnsupported
    case diagActionUnsupported
    case diagCallUnsupported
    case diagMethodUnsupported
    case diagFactoryUnsupported
    case diagForEachNeedsClosure
    case diagForEachData
    case diagModifierIgnored
    case diagMockNeeded
    case diagNoMockValue

    // MARK: Misc
    case fileLine              // %@ · 第 %d 行
    case apiName
    case resetPreviewState
    case workspaceError
}

/// Central localization service. Views read `L10nService.shared.t(.key)`;
/// because the service is `@Observable`, changing `language` re-renders.
@Observable
final class L10nService: @unchecked Sendable {
    static let shared = L10nService()

    private let defaultsKey = "codeberry.appLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Resolve `.system` against the device locale.
    var useChinese: Bool {
        switch language {
        case .zhHans: return true
        case .english: return false
        case .system:
            return Locale.current.language.languageCode == "zh"
        }
    }

    func t(_ key: L10nKey) -> String {
        guard let entry = Self.table[key] else { return key.rawValue }
        return useChinese ? entry.zh : entry.en
    }

    func t(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }

    // MARK: - String table

    private static let table: [L10nKey: (zh: String, en: String)] = [
        // §一-5
        .projects: ("项目", "Projects"),
        .newProject: ("新建项目", "New Project"),
        .newFile: ("新建 Swift 文件", "New Swift File"),
        .preview: ("预览", "Preview"),
        .files: ("文件", "Files"),
        .editor: ("编辑器", "Editor"),
        .settings: ("设置", "Settings"),
        .appearance: ("外观", "Appearance"),
        .language: ("语言", "Language"),
        .device: ("设备", "Device"),
        .light: ("浅色", "Light"),
        .dark: ("深色", "Dark"),
        .system: ("跟随系统", "System"),
        .inspector: ("检查器", "Inspector"),
        .apply: ("应用", "Apply"),
        .reset: ("重置", "Reset"),
        .exportPatch: ("导出补丁", "Export Patch"),
        .copyCode: ("复制代码", "Copy Code"),
        .warnings: ("警告", "Warnings"),
        .previewError: ("预览错误", "Preview Error"),
        .unsupported: ("暂不支持", "Unsupported"),
        .reload: ("重新加载", "Reload"),
        .save: ("保存", "Save"),
        .cancel: ("取消", "Cancel"),
        .create: ("创建", "Create"),
        // §一-6
        .errSyntaxError: ("无法预览：当前文件存在语法错误", "Can't preview: the current file has syntax errors."),
        .errUnsupportedAPI: ("暂不支持此 SwiftUI API：%@", "This SwiftUI API isn't supported yet: %@"),
        .errComponentNotFound: ("找不到组件 %@", "Component not found: %@"),
        .errPreviewPaused: ("预览已暂停", "Preview paused"),
        .errNoPreviewableView: ("无法预览：请添加遵循 View 的 struct 或 #Preview", "Nothing to preview — add a struct conforming to View or a #Preview block."),
        .errNoBody: ("%@ 没有可预览的 body", "%@ has no body to preview."),
        .errRecursionDeep: ("视图嵌套过深（可能是递归视图）", "View nesting too deep (recursive view?)."),
        // App chrome
        .appName: ("CodeBerry Lite", "CodeBerry Lite"),
        .done: ("完成", "Done"),
        .close: ("关闭", "Close"),
        .confirm: ("确认", "Confirm"),
        .delete: ("删除", "Delete"),
        .rename: ("重命名", "Rename"),
        .ok: ("好", "OK"),
        // Settings
        .settingsWorkspace: ("工作区", "Workspace"),
        .settingsLocation: ("位置", "Location"),
        .settingsLocationDesc: ("工作区就是 App 的文稿文件夹，在系统的文件 App 里也能看到。", "Your workspace is the app's Documents folder — files are also visible in the Files app."),
        .settingsAbout: ("关于", "About"),
        .settingsVersion: ("版本", "Version"),
        .settingsAboutDesc: ("CodeBerry Lite —— Swift 编辑器 + SwiftUI 预览画布，无 AI 智能体。", "CodeBerry Lite — Swift editor + SwiftUI preview canvas, no AI agent."),
        .languageFollowSystem: ("跟随系统", "Follow System"),
        .languageZhHans: ("简体中文", "简体中文"),
        .languageEnglish: ("English", "English"),
        // Projects
        .noProjects: ("还没有项目", "No Projects"),
        .noProjectsDesc: ("创建你的第一个项目，开始写代码。", "Create your first project to start coding."),
        .createAppProject: ("创建 App 项目", "Create App Project"),
        .createEmptyProject: ("创建空项目", "Create Empty Project"),
        .newProjectMessage: ("App 项目会带一个 SwiftUI 起始文件；空项目只是一个文件夹。", "App projects include a starter SwiftUI file; empty projects are just a folder."),
        .projectNamePlaceholder: ("名称，例如 PomodoroTimer", "Name, e.g. PomodoroTimer"),
        .renameProject: ("重命名项目", "Rename Project"),
        .newNamePlaceholder: ("新名称", "New name"),
        .deleteProjectMessage: ("这会删除整个项目文件夹，且无法撤销。", "This deletes the whole project folder and can't be undone."),
        .folderKind: ("文件夹", "Folder"),
        .iosAppKind: ("iOS App", "iOS App"),
        // File navigator
        .newFolder: ("新建文件夹", "New Folder"),
        .newFolderMessage: ("创建于%@。", "Created in %@."),
        .workspaceRoot: ("工作区根目录", "the workspace root"),
        .renameFile: ("重命名", "Rename"),
        .deleteFileMessage: ("此操作无法撤销。", "This can't be undone."),
        .backToProjects: ("项目", "Projects"),
        .navigatorEmptyDesc: ("点 + 新建 Swift 文件，开始搭建。", "Create a Swift file with + to start building."),
        // Editor
        .noFileOpen: ("没有打开文件", "No File Open"),
        .noFileOpenDesc: ("在文件列表中选择一个文件。", "Select a file in the navigator."),
        // Canvas toolbar
        .indexing: ("正在建立预览索引…", "Building preview index…"),
        .diagnostics: ("诊断", "Diagnostics"),
        .errorsOnly: ("只显示错误", "Errors only"),
        .showIgnored: ("已忽略", "Ignored"),
        .severityError: ("错误", "Error"),
        .severityWarning: ("警告", "Warning"),
        .severityIgnored: ("已忽略", "Ignored"),
        .orientation: ("方向", "Orientation"),
        .portrait: ("竖屏", "Portrait"),
        .landscape: ("横屏", "Landscape"),
        .safeArea: ("安全区", "Safe Area"),
        .deviceIPhoneAir: ("iPhone Air", "iPhone Air"),
        .deviceIPhonePro: ("iPhone Pro", "iPhone Pro"),
        .deviceIPhoneProMax: ("iPhone Pro Max", "iPhone Pro Max"),
        .deviceCompactIPhone: ("小屏iPhone", "Compact iPhone"),
        .deviceIPad: ("iPad", "iPad"),
        .followSystem: ("跟随系统", "Follow System"),
        .snapshot: ("快照", "Snapshot"),
        .more: ("更多", "More"),
        // Inspector
        .tapToInspect: ("轻点画布中的元素进行调整", "Tap an element on the canvas to adjust it"),
        .inspectorTitle: ("检查器", "Inspector"),
        .paramFontSize: ("字号", "Font Size"),
        .paramFontWeight: ("字重", "Font Weight"),
        .paramTextColor: ("文字颜色", "Text Color"),
        .paramLineLimit: ("行数限制", "Line Limit"),
        .paramSpacing: ("间距", "Spacing"),
        .paramAlignment: ("对齐", "Alignment"),
        .paramPadding: ("内边距", "Padding"),
        .paramWidth: ("宽度", "Width"),
        .paramHeight: ("高度", "Height"),
        .paramMinHeight: ("最小高度", "Min Height"),
        .paramMaxWidth: ("最大宽度", "Max Width"),
        .paramCornerRadius: ("圆角", "Corner Radius"),
        .paramOpacity: ("不透明度", "Opacity"),
        .paramFillColor: ("填充颜色", "Fill Color"),
        .paramStrokeWidth: ("描边宽度", "Stroke Width"),
        .applyToCode: ("应用到代码", "Apply to Code"),
        .previewOnlyNote: ("仅在预览中生效，不修改源码", "Preview-only, source untouched"),
        .showDiff: ("查看差异", "View Diff"),
        .confirmApplyTitle: ("确认应用到代码", "Confirm Apply to Code"),
        .writeFailed: ("写入失败，原文件未改动", "Write failed — the original file was left untouched"),
        .tokenComesFrom: ("此值来自设计令牌 %@", "This value comes from design token %@"),
        .tokenOverrideOnly: ("仅本次预览覆盖", "Override for this preview only"),
        .tokenEditDefinition: ("修改令牌定义", "Edit token definition"),
        .tokenAffectsMany: ("此修改可能影响多个页面", "This change may affect multiple screens"),
        .noSelection: ("未选中元素", "No element selected"),
        // Mock data
        .mockData: ("预览数据", "Preview Data"),
        .mockNeeded: ("此依赖需要 Mock 才能预览", "This dependency needs mock data to preview"),
        .mockAdd: ("添加 Mock", "Add Mock"),
        .mockKey: ("键", "Key"),
        .mockValue: ("值", "Value"),
        .mockEmpty: ("还没有预览数据", "No preview data yet"),
        // Fixture generation
        .generateFixture: ("生成预览夹具", "Generate Preview Fixture"),
        .fixtureGenerated: ("已生成 %@", "Generated %@"),
        // Patch export
        .viewDiff: ("查看差异", "View Diff"),
        .copyPatch: ("复制补丁", "Copy Patch"),
        .exportPatchFile: ("导出补丁文件", "Export Patch File"),
        .copyModifiedCode: ("复制修改后代码", "Copy Modified Code"),
        .diffTitle: ("代码差异", "Code Diff"),
        .noChanges: ("暂无修改", "No changes"),
        // Before / After
        .before: ("修改前", "Before"),
        .after: ("修改后", "After"),
        .saveSnapshot: ("保存快照", "Save Snapshot"),
        .snapshotSaved: ("已保存当前状态为“修改前”", "Saved current state as “Before”"),
        // Diagnostics
        .diagDeclInBody: ("body 内的声明暂不支持：%@", "Declarations inside body aren't supported: %@"),
        .diagExprNotView: ("该表达式不是视图：%@", "Expression isn't a view: %@"),
        .diagIfLet: ("预览暂不支持 `if let` / `if case`", "`if let` / `if case` aren't supported in previews yet."),
        .diagExprUnsupported: ("暂不支持的表达式：%@", "Expression not supported: %@"),
        .diagNotState: ("$%@ 不是 @State 属性", "$%@ isn't a @State property."),
        .diagUnknownIdentifier: ("未知标识符“%@”", "Unknown identifier \"%@\""),
        .diagMemberUnsupported: ("此处不支持 .%@", "Member '.%@' not supported here."),
        .diagOperatorUnsupported: ("暂不支持运算符“%@”", "Operator '%@' not supported."),
        .diagActionUnsupported: ("暂不支持的动作：%@", "Action not supported: %@"),
        .diagCallUnsupported: ("此处不支持调用 .%@(…)", "Call '.%@(…)' not supported here."),
        .diagMethodUnsupported: ("暂不支持方法 .%@(…)", "Method '.%@(…)' not supported."),
        .diagFactoryUnsupported: ("“%@”预览暂不支持", "'%@' isn't supported by the preview yet."),
        .diagForEachNeedsClosure: ("ForEach 需要范围/数组和尾随闭包", "ForEach needs a range/array and a trailing closure."),
        .diagForEachData: ("ForEach 数据必须是范围或数组字面量", "ForEach data must be a range or array literal."),
        .diagModifierIgnored: ("修饰符 .%@ 暂不支持（已忽略）", "Modifier '.%@' not supported (ignored)."),
        .diagMockNeeded: ("“%@”需要 Mock 数据才能预览", "\"%@\" needs mock data to preview."),
        .diagNoMockValue: ("缺少 Mock 值：%@", "Missing mock value: %@"),

        // Misc
        .fileLine: ("%1$@ · 第 %2$d 行", "%1$@ · line %2$d"),
        .apiName: ("API", "API"),
        .resetPreviewState: ("重置预览状态", "Reset Preview State"),
        .workspaceError: ("工作区错误", "Workspace Error"),
    ]
}
