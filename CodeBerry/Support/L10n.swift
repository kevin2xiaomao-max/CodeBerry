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

    // MARK: Workspace errors (§一-6, release cleanup)
    case errProjectNameInvalid  // 项目名称必须包含字母或数字。
    case errCreateProject       // 无法创建项目：%@
    case errProjectNameSlash    // 项目名称不能包含"/"。
    case errOpenNotUTF8         // 无法打开 %@ — 不是 UTF-8 文本文件。
    case errSaveFailed          // 保存失败：%@
    case errFileExists          // %@ 已存在。
    case errCreateFile          // 无法创建 %@：%@
    case errCreateFolder        // 无法创建文件夹：%@
    case errDeleteFailed        // 无法删除 %@：%@
    case errRenameFailed        // 无法重命名：%@

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
    case severityInfo        // 4.0.2 P1-9: 信息（不影响预览的说明）
    case severityNeedsMock   // 4.0.2 P1-9: 需要 Mock/Fixture
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
    case mockQueryFill          // @Query 数组填充方式
    case mockQueryEmpty         // 空
    case mockQuerySample        // 示例
    case mockQueryCount         // 数量

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
    case diagExternalPackageNotExecuted   // 4.0.2 P1-8: 「%@」属于外部包 %@，预览不执行
    case diagForEachNeedsClosure
    case diagForEachData
    case diagModifierIgnored
    case diagMockNeeded
    case diagNoMockValue
    case diagTypePreviewDefault   // 4.0.2 P0-3: 「%@」使用预览默认值

    // MARK: GitHub Direct (§8/§9, 4.0 M1)
    case githubImportTitle       // 从 GitHub 导入
    case githubOpenFromGitHub    // 从 GitHub 打开
    case githubURLLabel          // 仓库链接
    case githubURLPlaceholder    // https://github.com/owner/repo
    case githubParseHint         // 支持仓库主页 / tree / blob 链接，也支持 git@ SSH 形式
    case githubRepoCard          // 仓库
    case githubPrivateBadge      // 私有
    case githubPublicBadge       // 公开
    case githubRefSection        // 版本
    case githubRefBranch         // 分支
    case githubRefTag            // 标签
    case githubRefCommit         // 提交
    case githubDefaultBranchTag  // 默认
    case githubCommitSHAPlaceholder // 完整 commit SHA
    case githubImportAction      // 导入
    case githubImporting         // 正在导入…
    case githubDownloading       // 正在下载…
    case githubExtracting        // 正在解压…
    case githubImportDone        // 导入完成
    case githubRecentTitle       // 最近导入
    case githubNoRecent          // 还没有从 GitHub 导入过仓库
    case githubSyncAction        // 同步 GitHub
    case githubSyncing           // 正在同步…
    case githubSyncedUpToDate    // 已是最新
    case githubSyncApplied       // 已更新 %d 个文件
    case githubSyncConflicts     // %d 个文件存在冲突，已保留你的本地修改
    case githubSyncFailed        // 同步失败
    case githubLastSync          // 上次同步：%@
    case githubNeverSynced       // 尚未同步
    case githubTokenSection      // GitHub 令牌
    case githubTokenDesc         // 用于访问私有仓库、提高 API 配额。只保存在钥匙串中。
    case githubTokenPlaceholder  // ghp_… / github_pat_…
    case githubTokenSaved        // 令牌已保存到钥匙串
    case githubTokenDeleted      // 令牌已删除
    case githubTokenSet          // 已设置
    case githubTokenNotSet       // 未设置
    case githubSaveToken         // 保存令牌
    case githubDeleteToken       // 删除令牌
    case githubOpenFileAfterImport // 导入后打开的文件不存在，已打开仓库根目录
    case githubNotAProject       // 不是 GitHub 导入的项目
    case githubSyncPlanTitle     // 同步计划
    case githubSyncConfirm       // 确认应用
    case githubWillApply         // 将应用以下更改
    case githubConflictsNeedResolve // 以下冲突需要手动处理
    case switchWorkspace         // 切换 Workspace
    // GitHub errors
    case errGithubInvalidURL     // 不是有效的 GitHub 仓库链接
    case errGithubNetwork        // 网络错误：%@
    case errGithubHTTP           // GitHub 返回错误 %d：%@
    case errGithubRateLimited    // API 配额已用完，%@ 后恢复（可添加令牌提高配额）
    case errGithubRateLimitedUnknown // API 配额已用完（可添加令牌提高配额）
    case errGithubNotFound       // 找不到仓库 %@
    case errGithubUnauthorized   // 令牌无效或已过期
    case errGithubDecoding       // 解析 GitHub 返回数据失败
    case errGithubCancelled      // 已取消
    case errGithubNoToken        // 未设置 GitHub 令牌
    case errGithubTokenEmpty     // 令牌不能为空
    case errGithubTokenFormat    // 令牌格式不正确（应为 ghp_… 或 github_pat_…）
    case errArchiveUnreadable    // 无法读取下载的压缩包
    case errArchiveTooManyEntries // 压缩包条目过多（%d），已拒绝解压
    case errArchiveTooLarge      // 压缩包解压后超过 %@，已拒绝解压
    case errArchiveSymlink       // 压缩包包含符号链接 %@，已拒绝解压
    case errArchiveTraversal     // 压缩包包含非法路径 %@，已拒绝解压
    case errArchiveAbsolutePath  // 压缩包包含绝对路径 %@，已拒绝解压

    // MARK: - M2: Editor
    case quickOpenTitle         // 快速打开
    case quickOpenFiles         // 文件
    case quickOpenSymbols       // 符号
    case quickOpenCommands      // 命令
    case quickOpenSearchHint    // 搜索文件、符号、命令
    case cmdProjectSearch       // 在项目中搜索
    case cmdJumpToDefinition    // 跳转到定义
    case cmdFindReferences      // 查找引用
    case cmdRebuildIndex        // 重建符号索引
    case cmdShowDiagnostics     // 查看诊断信息
    case projectSearchTitle     // 项目搜索
    case projectSearchHint      // 在项目中搜索
    case projectSearchCase      // 区分大小写
    case diagnosticsTitle       // 诊断
    case diagnosticsEmpty       // 当前文件没有语法错误
    case diagnosticsNone        // 无诊断信息
    case referencesTitle        // 引用：%@
    case referencesEmpty        // 无引用
    case referencesEmptyDesc    // 在项目中没有找到 %@ 的其他引用
    case symbolLineInfo         // %@ · %@ · 行 %d
    case diagnosticPosition     // 行 %d，列 %d

    // MARK: Misc
    case fileLine              // %@ · 第 %d 行
    case apiName
    case resetPreviewState
    case workspaceError

    // MARK: M3 — Preview Engine 2
    case candidatesTitle       // 可预览页面
    case searchCandidates      // 搜索页面
    case noCandidates          // 未找到可预览页面
    case readinessReady        // 可直接预览
    case readinessNeedsMock    // 需要 Mock
    case readinessMissingComponent // 缺少自定义组件支持
    case readinessExternalPackage  // 外部 Package 不执行
    case readinessSyntaxError  // 语法错误
    case readinessUnsupportedRuntime // 不支持的运行时依赖
    case actionGenerateFixture // 生成 Preview Fixture
    case actionCreateMock      // 创建 Mock
    case actionIgnoreNonVisual // 忽略非视觉依赖
    case actionViewDiagnostics // 查看 Diagnostics
    case dashboardTitle        // 兼容性总览
    case levelSupported        // 支持
    case levelApproximate      // 近似
    case levelCosmeticIgnore   // 忽略
    case levelUnsupported      // 不支持
    case mockCenterTitle       // Mock 中心
    case profile               // Profile
    case mockValues            // Mock 值
    case addProfile            // 新增 Profile
    case profileName           // Profile 名称
    case jumpToCode            // 跳到代码
    case reorderModifiers      // 调整 Modifier 顺序
    case resetOneParam         // 重置此参数
    case tokenRefCount         // 预计影响 %d 处引用
    case beforeAfterVisual     // 前后对比（视觉）
    case captureBefore         // 保存修改前快照
    case beforeLabel           // 修改前
    case afterLabel            // 修改后
    case locateInPreview       // 在预览中定位
    case pages                 // 页面
    case mockCenter            // Mock 中心
    case compatibility         // 兼容性
    case hideReadiness         // 不再提示
    case reorderUnsafeNote       // 该 modifier 不支持安全重排（可能改变渲染结果）
    case conflictKeepLocal  // 保留本地
    case conflictUseRemote  // 使用远端
    case conflictManualMerge  // 手动合并
    case conflictsTitle  // 冲突
    case conflictBothModified  // 本地和远端都修改了此文件
    case conflictDeleteVsModify  // 一端删除、另一端修改了此文件
    case historyTitle  // 本地历史
    // MARK: M5 — four-tab navigation
    case filesTab  // 文件
    case codeTab  // 代码
    case previewTab  // 预览
    case previewNoFile  // 未打开文件
    case previewNoFileHint  // 在「文件」中选择一个 Swift 文件进行预览
    case historyEmpty  // 暂无历史版本
    case historyRestore  // 恢复
    case bytesUnit  // 字节
    case changesTab  // 更改
    case localChangesTitle  // 本地更改
    case noLocalChanges  // 没有本地更改
    case changeAdded  // 新增
    case changeModified  // 已修改
    case changeDeleted  // 已删除
    case syncNow  // 立即同步
    case offlineMessage  // 离线 — 同步与下载已暂停
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
        // Workspace errors
        .errProjectNameInvalid: ("项目名称必须包含字母或数字。", "Project name must contain letters or digits."),
        .errCreateProject: ("无法创建项目：%@", "Couldn't create project: %@"),
        .errProjectNameSlash: ("项目名称不能包含\"/\"。", "Project names can't contain \"/\"."),
        .errOpenNotUTF8: ("无法打开 %@ — 不是 UTF-8 文本文件。", "Can't open %@ — not a UTF-8 text file."),
        .errSaveFailed: ("保存失败：%@", "Save failed: %@"),
        .errFileExists: ("%@ 已存在。", "%@ already exists."),
        .errCreateFile: ("无法创建 %@：%@", "Couldn't create %@: %@"),
        .errCreateFolder: ("无法创建文件夹：%@", "Couldn't create folder: %@"),
        .errDeleteFailed: ("无法删除 %@：%@", "Couldn't delete %@: %@"),
        .errRenameFailed: ("无法重命名：%@", "Couldn't rename: %@"),
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
        .severityInfo: ("信息", "Info"),
        .severityNeedsMock: ("需要 Mock", "Needs Mock"),
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
        .mockQueryFill: ("@Query 数组填充", "@Query array fill"),
        .mockQueryEmpty: ("空", "Empty"),
        .mockQuerySample: ("示例", "Sample"),
        .mockQueryCount: ("数量", "Count"),
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
        .diagExternalPackageNotExecuted: ("“%@”属于外部包 %@，预览不执行", "'%@' is from external package %@ and is not executed in preview."),
        .diagForEachNeedsClosure: ("ForEach 需要范围/数组和尾随闭包", "ForEach needs a range/array and a trailing closure."),
        .diagForEachData: ("ForEach 数据必须是范围或数组字面量", "ForEach data must be a range or array literal."),
        .diagModifierIgnored: ("修饰符 .%@ 暂不支持（已忽略）", "Modifier '.%@' not supported (ignored)."),
        .diagMockNeeded: ("“%@”需要 Mock 数据才能预览", "\"%@\" needs mock data to preview."),
        .diagNoMockValue: ("缺少 Mock 值：%@", "Missing mock value: %@"),
        .diagTypePreviewDefault: ("「%@」使用预览默认值", "\"%@\" uses preview defaults"),

        // GitHub Direct (4.0 M1)
        .githubImportTitle: ("从 GitHub 导入", "Import from GitHub"),
        .githubOpenFromGitHub: ("从 GitHub 打开", "Open from GitHub"),
        .githubURLLabel: ("仓库链接", "Repository URL"),
        .githubURLPlaceholder: ("https://github.com/owner/repo", "https://github.com/owner/repo"),
        .githubParseHint: ("支持仓库主页 / tree / blob 链接，也支持 git@ SSH 形式", "Supports repo home / tree / blob links, and git@ SSH forms"),
        .githubRepoCard: ("仓库", "Repository"),
        .githubPrivateBadge: ("私有", "Private"),
        .githubPublicBadge: ("公开", "Public"),
        .githubRefSection: ("版本", "Version"),
        .githubRefBranch: ("分支", "Branch"),
        .githubRefTag: ("标签", "Tag"),
        .githubRefCommit: ("提交", "Commit"),
        .githubDefaultBranchTag: ("默认", "Default"),
        .githubCommitSHAPlaceholder: ("完整 commit SHA", "Full commit SHA"),
        .githubImportAction: ("导入", "Import"),
        .githubImporting: ("正在导入…", "Importing…"),
        .githubDownloading: ("正在下载…", "Downloading…"),
        .githubExtracting: ("正在解压…", "Extracting…"),
        .githubImportDone: ("导入完成", "Import complete"),
        .githubRecentTitle: ("最近导入", "Recently imported"),
        .githubNoRecent: ("还没有从 GitHub 导入过仓库", "No GitHub imports yet"),
        .githubSyncAction: ("同步 GitHub", "Sync GitHub"),
        .githubSyncing: ("正在同步…", "Syncing…"),
        .githubSyncedUpToDate: ("已是最新", "Already up to date"),
        .githubSyncApplied: ("已更新 %d 个文件", "Updated %d files"),
        .githubSyncConflicts: ("%d 个文件存在冲突，已保留你的本地修改", "%d files have conflicts; your local changes were kept"),
        .githubSyncFailed: ("同步失败", "Sync failed"),
        .githubLastSync: ("上次同步：%@", "Last sync: %@"),
        .githubNeverSynced: ("尚未同步", "Never synced"),
        .githubTokenSection: ("GitHub 令牌", "GitHub Token"),
        .githubTokenDesc: ("用于访问私有仓库、提高 API 配额。只保存在钥匙串中。", "For private repos and higher API quotas. Stored in the Keychain only."),
        .githubTokenPlaceholder: ("ghp_… / github_pat_…", "ghp_… / github_pat_…"),
        .githubTokenSaved: ("令牌已保存到钥匙串", "Token saved to the Keychain"),
        .githubTokenDeleted: ("令牌已删除", "Token deleted"),
        .githubTokenSet: ("已设置", "Set"),
        .githubTokenNotSet: ("未设置", "Not set"),
        .githubSaveToken: ("保存令牌", "Save Token"),
        .githubDeleteToken: ("删除令牌", "Delete Token"),
        .githubOpenFileAfterImport: ("导入后打开的文件不存在，已打开仓库根目录", "The linked file wasn't in the snapshot; opened the repo root"),
        .githubNotAProject: ("不是 GitHub 导入的项目", "Not a GitHub project"),
        .githubSyncPlanTitle: ("同步计划", "Sync Plan"),
        .githubSyncConfirm: ("确认应用", "Apply"),
        .githubWillApply: ("将应用以下更改", "The following changes will be applied"),
        .githubConflictsNeedResolve: ("以下冲突需要手动处理", "These conflicts need manual resolution"),
        .switchWorkspace: ("切换 Workspace", "Switch Workspace"),
        .errGithubInvalidURL: ("不是有效的 GitHub 仓库链接", "Not a valid GitHub repository URL"),
        .errGithubNetwork: ("网络错误：%@", "Network error: %@"),
        .errGithubHTTP: ("GitHub 返回错误 %d：%@", "GitHub error %d: %@"),
        .errGithubRateLimited: ("API 配额已用完，%@ 后恢复（可添加令牌提高配额）", "API quota exhausted, resets %@ (add a token for a higher quota)"),
        .errGithubRateLimitedUnknown: ("API 配额已用完（可添加令牌提高配额）", "API quota exhausted (add a token for a higher quota)"),
        .errGithubNotFound: ("找不到仓库 %@", "Repository not found: %@"),
        .errGithubUnauthorized: ("令牌无效或已过期", "Token is invalid or expired"),
        .errGithubDecoding: ("解析 GitHub 返回数据失败", "Failed to parse GitHub response"),
        .errGithubCancelled: ("已取消", "Cancelled"),
        .errGithubNoToken: ("未设置 GitHub 令牌", "No GitHub token set"),
        .errGithubTokenEmpty: ("令牌不能为空", "Token must not be empty"),
        .errGithubTokenFormat: ("令牌格式不正确（应为 ghp_… 或 github_pat_…）", "Unrecognized token format (expected ghp_… or github_pat_…)"),
        .errArchiveUnreadable: ("无法读取下载的压缩包", "Cannot read the downloaded archive"),
        .errArchiveTooManyEntries: ("压缩包条目过多（%@），已拒绝解压", "Archive has too many entries (%@); extraction refused"),
        .errArchiveTooLarge: ("压缩包解压后超过 %@，已拒绝解压", "Archive would extract beyond %@; extraction refused"),
        .errArchiveSymlink: ("压缩包包含符号链接 %@，已拒绝解压", "Archive contains symlink %@; extraction refused"),
        .errArchiveTraversal: ("压缩包包含非法路径 %@，已拒绝解压", "Archive contains illegal path %@; extraction refused"),
        .errArchiveAbsolutePath: ("压缩包包含绝对路径 %@，已拒绝解压", "Archive contains absolute path %@; extraction refused"),

        // M2: Editor
        .quickOpenTitle: ("快速打开", "Quick Open"),
        .quickOpenFiles: ("文件", "Files"),
        .quickOpenSymbols: ("符号", "Symbols"),
        .quickOpenCommands: ("命令", "Commands"),
        .quickOpenSearchHint: ("搜索文件、符号、命令", "Search files, symbols, commands"),
        .cmdProjectSearch: ("在项目中搜索", "Search in Project"),
        .cmdJumpToDefinition: ("跳转到定义", "Jump to Definition"),
        .cmdFindReferences: ("查找引用", "Find References"),
        .cmdRebuildIndex: ("重建符号索引", "Rebuild Symbol Index"),
        .cmdShowDiagnostics: ("查看诊断信息", "Show Diagnostics"),
        .projectSearchTitle: ("项目搜索", "Project Search"),
        .projectSearchHint: ("在项目中搜索", "Search in project"),
        .projectSearchCase: ("区分大小写", "Case sensitive"),
        .diagnosticsTitle: ("诊断", "Diagnostics"),
        .diagnosticsEmpty: ("当前文件没有语法错误", "No syntax errors in this file"),
        .diagnosticsNone: ("无诊断信息", "No diagnostics"),
        .referencesTitle: ("引用：%@", "References: %@"),
        .referencesEmpty: ("无引用", "No references"),
        .referencesEmptyDesc: ("在项目中没有找到 %@ 的其他引用", "No other references to %@ found in the project"),
        .symbolLineInfo: ("%1$@ · %2$@ · 行 %3$d", "%1$@ · %2$@ · line %3$d"),
        .diagnosticPosition: ("行 %1$d，列 %2$d", "Line %1$d, column %2$d"),

        // Misc
        .fileLine: ("%1$@ · 第 %2$d 行", "%1$@ · line %2$d"),
        .apiName: ("API", "API"),
        .resetPreviewState: ("重置预览状态", "Reset Preview State"),
        .workspaceError: ("工作区错误", "Workspace Error"),
        // M3
        .candidatesTitle: ("可预览页面", "Previewable Pages"),
        .searchCandidates: ("搜索页面", "Search pages"),
        .noCandidates: ("未找到可预览页面", "No previewable pages found"),
        .readinessReady: ("可直接预览", "Ready to preview"),
        .readinessNeedsMock: ("需要 Mock", "Needs Mock"),
        .readinessMissingComponent: ("缺少自定义组件支持", "Missing component support"),
        .readinessExternalPackage: ("外部 Package 不执行", "External package not executed"),
        .readinessSyntaxError: ("语法错误", "Syntax error"),
        .readinessUnsupportedRuntime: ("不支持的运行时依赖", "Unsupported runtime dependency"),
        .actionGenerateFixture: ("生成 Preview Fixture", "Generate Preview Fixture"),
        .actionCreateMock: ("创建 Mock", "Create Mock"),
        .actionIgnoreNonVisual: ("忽略非视觉依赖", "Ignore non-visual dependencies"),
        .actionViewDiagnostics: ("查看 Diagnostics", "View Diagnostics"),
        .dashboardTitle: ("兼容性总览", "Compatibility Dashboard"),
        .levelSupported: ("支持", "Supported"),
        .levelApproximate: ("近似", "Approximate"),
        .levelCosmeticIgnore: ("忽略", "Ignored"),
        .levelUnsupported: ("不支持", "Unsupported"),
        .mockCenterTitle: ("Mock 中心", "Mock Center"),
        .profile: ("Profile", "Profile"),
        .mockValues: ("Mock 值", "Mock Values"),
        .addProfile: ("新增 Profile", "Add Profile"),
        .profileName: ("Profile 名称", "Profile name"),
        .jumpToCode: ("跳到代码", "Jump to Code"),
        .reorderModifiers: ("调整 Modifier 顺序", "Reorder Modifiers"),
        .resetOneParam: ("重置此参数", "Reset this parameter"),
        .tokenRefCount: ("预计影响 %d 处引用", "Affects ~%d references"),
        .beforeAfterVisual: ("前后对比（视觉）", "Before / After (visual)"),
        .captureBefore: ("保存修改前快照", "Capture Before Snapshot"),
        .beforeLabel: ("修改前", "Before"),
        .afterLabel: ("修改后", "After"),
        .locateInPreview: ("在预览中定位", "Locate in Preview"),
        .pages: ("页面", "Pages"),
        .mockCenter: ("Mock 中心", "Mock Center"),
        .compatibility: ("兼容性", "Compatibility"),
        .hideReadiness: ("不再提示", "Don't show again"),
        .reorderUnsafeNote: ("该 modifier 不支持安全重排（可能改变渲染结果）", "This modifier cannot be safely reordered (may change rendering)"),
        .conflictKeepLocal: ("保留本地", "Keep Local"),
        .conflictUseRemote: ("使用远端", "Use Remote"),
        .conflictManualMerge: ("手动合并", "Manual Merge"),
        .conflictsTitle: ("冲突", "Conflicts"),
        .conflictBothModified: ("本地和远端都修改了此文件", "Modified both locally and remotely"),
        .conflictDeleteVsModify: ("一端删除、另一端修改了此文件", "Deleted on one side, modified on the other"),
        .historyTitle: ("本地历史", "Local History"),
        .filesTab: ("文件", "Files"),
        .codeTab: ("代码", "Code"),
        .previewTab: ("预览", "Preview"),
        .previewNoFile: ("未打开文件", "No File Open"),
        .previewNoFileHint: ("在「文件」中选择一个 Swift 文件进行预览", "Pick a Swift file in Files to preview"),
        .historyEmpty: ("暂无历史版本", "No revisions yet"),
        .historyRestore: ("恢复", "Restore"),
        .bytesUnit: ("字节", "bytes"),
        .changesTab: ("更改", "Changes"),
        .localChangesTitle: ("本地更改", "Local Changes"),
        .noLocalChanges: ("没有本地更改", "No local changes"),
        .changeAdded: ("新增", "Added"),
        .changeModified: ("已修改", "Modified"),
        .changeDeleted: ("已删除", "Deleted"),
        .syncNow: ("立即同步", "Sync Now"),
        .offlineMessage: ("离线 — 同步与下载已暂停", "Offline — sync and download paused"),
    ]
}
