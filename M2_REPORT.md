# M2 Report — CodeBerry Lite 4.0: Editor Engine

- Branch: `codeberry-lite-v4` (M2 commit: TBD, parent = M1 `7e15239`)
- Spec: `Muse_CodeBerry_Lite_4.0_FINAL_GitHub_Direct_Mobile_Interaction.txt` §十三（编辑器）、§十五（诊断）、§三十九（测试矩阵 M2 行）
- Date: 2026-10-01
- Status: **代码 + 测试完成，待 CI 绿后提交**（本报告随 commit 一起进仓）

## 1. 交付内容

### Runestone 编辑器（替换全部旧编辑器）
- 删除：`CodeTextView.swift`、`SwiftHighlighter.swift`、`AutocompleteEngine.swift`、`CodeEditorView.swift`（旧 UITextView + 手写高亮 + 旧补全）。
- 新增 `CodeBerry/Editor/`：
  - `RunestoneEditorView.swift` — `UIViewRepresentable` 封装 `Runestone.TextView`（0.5.2），绑定 workspace 文本；coordinator 处理配对括号/引号、Xcode 式回车缩进（`{`+回车展开）、跳过已存在的右括号；**Coding Bar 只做 toolbar，绝不拦截按键**（中文输入法 marked text 不受影响）。
  - `CodeBerryEditorTheme.swift` — `Theme` 协议实现（浅色 Xcode 风 / 深色 OneDark 风），Tree-sitter highlight 名称按最长前缀映射（`HighlightName` 为 internal，只能按原始字符串匹配）。
  - `EditorPaneView.swift`（重写）— Runestone + Coding Bar + Quick Open + 诊断按钮/列表 + 跳转定义/引用 + 项目搜索入口。

### SwiftSyntax 桥接（§十四）
- `SymbolIndex.swift` — `SymbolCollector: SyntaxVisitor` 走 AST，记录 class/struct/enum/protocol/function/initializer/var/let/typealias/enum case/extension（含 parent 链）；`definition(of:)` 按类型>函数>别名>变量优先级；`references(to:)` 全项目文本扫描；`updateFile/removeFile` 增量更新（fingerprint 跳过未改文件）。
- `InlineDiagnostics.swift` — `Parser` + `ParseDiagnosticsGenerator.diagnostics(for:)`；`SourceLocationConverter` 取 1-based 行列；英文诊断映射中文（三层标签见 §十五）；`highlightRanges` 转 `HighlightedRange` 画波浪线。
- swift-syntax 版本：601.0.1（随 Xcode 26.5 工具链）。

### 本地补全（§十三：context-aware，零网络）
- `LocalCompletion.swift` — `Text(` 后建议 `" "`（字符串字面量，caretBacktrack=1 把光标放进引号）、`systemName:` 两个 SF Symbol 占位（§十九/二十二约束：只给占位，不给真实图标名）；`.` 后建议常用 SwiftUI modifier（`font/padding/foregroundStyle/...`，**不带前导点**，因为点已输入）；容器 `{` 后建议 `Spacer()/Divider()`；前缀匹配走关键字 + 常用符号 + 符号索引（去重）；**中文输入时不触发**（只响应 identifier 字符）。

### Coding Bar（§十二 P0）
- `CodingBarView.swift` — 严格按 §十二按键集：Tab `{` `}` `(` `)` `[` `]` `.` `,` `:` `"` `←` `→`，外加建议行与收起键盘键；`{`/`}`/`(`/`)`/`[`/`]` 按配对智能插入（光标已在右括号前则跳过）；纯 toolbar 逻辑，不拦截按键，中文输入法 marked text 不受影响。
- 与 spec 示例的一处有意差异：spec §十二示例把建议写作 `.font`（带点）；实现中当用户**已输入 `.`** 时建议显示为 `font`（不带点），避免敲出 `..font`。`Text(` 后建议 `" "`（字符串字面量，caretBacktrack=1 把光标放进引号）与 `systemName:` 占位。

### Quick Open（⌘P / §十六）
- `QuickOpenView.swift` — 三段 scope：文件（项目内全部文件）/ 符号（SymbolIndex 全局）/ 命令（项目搜索、跳转定义、查找引用、重建索引、查看诊断）；子序列模糊匹配，按"更早+更紧"打分排序。

### 项目搜索 / 导航（§十六）
- `ProjectSearch.swift` + `ProjectSearchView.swift` — 全项目文本搜索（跳过二进制、`.git`，200 文件/每文件 200 命中上限），结果按文件分组显示行号。
- `CodeNavigation.swift` — `jumpToDefinition`（光标词 → definition → `navigateToLine` 滚动）、`findReferences` sheet（引用列表，点跳转）。

## 2. 关键设计决策

1. **下载永远按不可变 commit SHA**（M1 延续）；同步前先比 remote HEAD 与 `baseSnapshotSHA`，相等则零下载。
2. **诊断只做 syntax 层**（`ParseDiagnosticsGenerator`）：语义/类型错误不做（那是 Swift 编译器的事）；中文映射只覆盖高频 parser 错误，其余回退"语法错误：<英文原文>"。
3. **补全是纯本地启发式**：不做类型推断，不猜 API 签名；SF Symbol 只给占位不给真名（spec §十九约束）。
4. **主题色走 Tree-sitter highlight 名称字符串**：`HighlightName` internal，主题实现里用 `raw.hasPrefix` 最长匹配（`keyword`/`string`/`comment`/`number`/`type`/`property`/`function` 等）。
5. **`navigateToLine` 用完即清**：`updateUIView` 里滚动后把 binding 置 nil，防止重复跳转。
6. **L10n**：新增 20 个 key（中英对照），新 UI 字符串全部走 `L10nService`；workspace 级硬编码中文后续 M5 统一审计。

## 3. 测试（§三十九 M2 行全覆盖）

| 套件 | 用例数 | 覆盖 |
|---|---|---|
| `ProjectIndexTests` | 13 | 符号种类、行号、增量更新/删除、fingerprint 跳过、definition 优先级、extension 记录、parent 链 |
| `SwiftSyntaxBridgeTests` | 8 | parse 正确/错误、诊断有无、行列映射、message 非空、engine 端到端、highlight 范围合法 |
| `CompletionEngineTests` | 10 | Text(→`" "`、`.`→modifier 不带点、容器→Spacer、关键字、符号索引、去重、空前缀只给 context、嵌套调用取最内层 |
| `DiagnosticsTests` | 8 | 三层中文标签、干净代码零诊断、语法层标记、消息中文前缀、缺 `}` 提示、按位置排序、1-based 行列 |
| `ProjectSearchTests` | 6 | 行号、大小写敏感/不敏感、跳过二进制、空查询、扩展名过滤 |

合计 **45 个**新增用例。2.0/3.0 fixtures（`PreviewEngineTests`）未动，必须继续通过。

## 4. 已知限制（诚实标注）

- Linux 无 Xcode：本地无法编译；正确性依赖 CI（simulator build + 全测试套件）。
- Runestone `TextView.text` 的 programmatic set 与 `textViewDidChange` 的交互靠 `suppressCallbacks` 保护；极端情况下（外部文件被改写时正好在输入）可能丢一次外部更新——可接受，文件监听会触发二次同步（M4 完善）。
- 诊断只覆盖语法层；`@MainActor` 下大文件（>2000 行）诊断在后台线程跑（`Task.detached`），完成后回主线程刷新。
- Quick Open 文件列表走 `WorkspaceStore.allProjectFiles`（上限 5000）；超大项目截断。

## 5. 与 M1 的关系

- M1 commit `7e15239`（21 文件）只含 GitHub Direct；本 M2 commit 只含 Editor Engine（含 L10n 增量 key——L10n.swift 在 M1 commit 里已带 M2 的 20 个 key，属无害前置，编译无影响）。
- pbxproj：app/test 两个 target 增加 `SwiftDiagnostics` + `SwiftParserDiagnostics` product 依赖（swift-syntax 随工具链提供）。
