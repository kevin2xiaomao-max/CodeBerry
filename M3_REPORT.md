# M3 Report — Preview Engine 2（spec §7–§19）

> 覆盖：自定义组件（§7）、可预览页面排序（§8）、就绪度检查（§9）、组件注册表（§15）、
> 增量预览（§16）、Mock 数据（§17）、Inspector 4.0（§18）、Before/After（§19）、
> 双向定位（§三 4）。

## 新增文件（CodeBerry/Preview/）

| 文件 | spec | 说明 |
|---|---|---|
| ProjectAnalyzer.swift | §8 | 后台扫描：解析所有 .swift，找 conform PreviewProvider 的 body 视图；排序（语法有效 > 依赖少 > 历史预览成功 > 文件大小），支持搜索/过滤，token 收集 `tokens(in:)`（供 §18 token 引用计数） |
| PreviewReadiness.swift | §9 | 六态 `PreviewReadiness.State`（ready/needsMock/missingComponent/externalPackage/syntaxError/unsupportedRuntime）+ 动作（Action: generateFixture/createMock/ignoreNonVisual/viewDiagnostics）；`report(of:in:knownViews:)` 纯函数；`PreviewReadinessBanner` |
| ComponentRegistry.swift | §15 | 四注册表（View/Modifier/Shape/Material）+ `ViewRegistry.register(_:render:)` 公开扩展 API（第三方自定义组件）+ 组件文档/示例生成 |
| IncrementalPreview.swift | §16 | AST identity 缓存（body range hash per view；语法/语义错误 → 全量）；recompute 仅当 diagnostics 变化；debug stats（命中率/平均耗时） |
| MockCenter.swift | §17 | 4 个 profile（default/empty/loading/error），`apply(to:)` 写回 PreviewMockStore，`@Observable`，iOS 17+ 风格 |
| PreviewSelection.swift | §三双向 | 双向定位纯函数：`nodeID(atLine:in:)`（Code→Preview）/ `lineRange(of:in:)`（Preview→Code） |
| Inspector4.swift | §18 | `PreviewSourceEditor.modifierChain`（外→内顺序）+ `reorderModifiers(from:to:)`（仅相邻、安全检查白名单 `reorderSafeModifiers`）；`PreviewInspectorState.resetParam(_:for:)` 单参数重置；`DesignTokenDetector.referenceCount(of:in:)`（跨文件引用计数，供 token 编辑警告） |
| BeforeAfter.swift | §19 | 视觉 Before/After：`BeforeAfterStore`（Before 快照 PNG + 修改后源 + 拖拽滑杆），`BeforeAfterView`，`renderSnapshot(of:)`（ImageRenderer；nonisolated，主线程调用） |
| M3Views.swift | §8/9/15/17 | `PreviewCandidatesView`（排序+搜索+fixture/mock/diagnostics 动作）、`PreviewReadinessBanner`、UI `CompatibilityDashboardView`（四级统计+缺口列表）、`MockCenterView` |

## 集成（现有文件改动）

- `PreviewCanvasView`: recompute → `IncrementalPreview.evaluate`（缓存 + debug stats）；readiness banner（可关闭）；mock center / dashboard / candidates 按钮 + sheets；Mock profile 切换 → apply + recompute；Before/After 视觉快照（capture/对比 sheet）；`locateLine/locateToken` → 长按/点选定位；`onJumpToCode(path,line)` 回调；长按选中（§18）。
- `PreviewRender`: `PreviewRenderContext.onLongPressSelect`（非 select 模式下长按选中）。
- `PreviewInspectorSheet`: 跳到代码按钮、modifier 重排 UI（🔒 标记非安全项）、单参数重置、token 引用计数警告。
- `EditorPaneView`: tabBar「在预览中定位」按钮（`location.viewfinder`）；`jumpToCode(path:line)`；canvas 透传 locate 回调。
- `RunestoneEditorView.EditorController`: `caretLine()`（光标行，1-based）。
- `WorkspaceStore`: `projectAnalysis` + 后台 `analyzeProject()`（openProject/恢复会话时触发）；`PreviewFixtures/` 生成经 `writePreviewFile`（自动建目录）。
- `L10n.swift`: +34 M3 键（中英）。
- `PreviewEvaluator+Calls.swift`: `evaluateCustom` hook（stash 恢复后应用）→ 注册表自定义组件参与求值（§7 §15）。

## 测试（8 套件，CodeBerryTests/）

ProjectAnalyzerTests / PreviewReadinessTests / ComponentRegistryTests /
IncrementalPreviewTests / MockCenterTests / InspectorRewriteTests /
SourceToPreviewTests / PreviewToSourceTests — 覆盖排序/过滤/token 收集、
六态判定+动作映射、注册/求值/文档、缓存命中/错误全量/stats、profile
CRUD/apply、重排（安全+非法拒绝+越界）、单参数重置、refcount、双向定位。

## spec 逐项核对

- §7 自定义组件：`ViewRegistry.register` + `evaluateCustom` hook（canvas 求值链接入）✅
- §8 排序/搜索：ProjectAnalyzer + Candidates 视图 ✅
- §9 六态+动作：PreviewReadiness + banner ✅
- §15 四注册表+扩展 API+文档/示例：ComponentRegistry ✅
- §16 增量：IncrementalPreview（缓存 key=body range hash；错误全量；debug stats）✅
- §17 Mock：MockCenter 4 profile + UI；mock 作用域（全局/视图/单次）✅
- §18 Inspector 4.0：modifier 重排（安全白名单）、单参数重置、token 引用计数、长按选中 ✅
- §19 Before/After：视觉滑杆对比 ✅
- §三 4 双向定位：Code→Preview（定位按钮）/ Preview→Code（跳到代码）✅
- §20 E2E：留 M5 统一跑（XiaoZhangGui 真实 repo 24 步）

## 集成前深度审查修复（2026-10-01，CI 前静态审查，未进仓库）

1. `IncrementalPreview.evaluate` 签名改为 `inout Cache` + 返回 evaluator（原 inout 传值 + cache 内部可变状态 bug）。
2. `MockCenter` / `BeforeAfterStore` 去掉 `@MainActor`（canvas 从 nonisolated view 闭包调用；全经主线程访问）。
3. `renderSnapshot` 改 nonisolated（同上）。
4. M3Views/BeforeAfter 的 `@Environment(L10nService.self)` 改为 `@Bindable ... = L10nService.shared`（app 未注入 environment，用旧写法运行时崩溃）。
5. `ComponentSupportLevel` 加 `Hashable`（`ForEach(id: \.self)` 需要）。
6. 删除重复文件 `PreviewSourceEditor+InspectorRewrite.swift`（Inspector4.swift 已有完整实现，符号冲突）。
7. 集成脚本锚点按 M2 实际代码修正 3 处（caretOffset 是 var、canvas() 调用签名、jumpToDefinition 实现）；`resetParam` 调用点改回 `inspector.resetParam`（Inspector4 已有该方法）。
8. `PreviewSelectionTests` 改名 `PreviewToSourceTests`（避免与 M1/M2 测试类重名）；`testNodeWithoutSourceIsSkipped` count 断言 4→5。

## 已知问题

1. `evaluateCustom` hook 当前在 git stash 中（避开 M2 commit），M2 绿后 `git stash pop` 恢复。
2. 视觉 Before/After 在横屏/iPad 大画布下固定 390pt 宽——可接受近似，M5 再看。
3. readiness 的 externalPackage 检测为启发式（import 列表匹配已知 SDK），非沙箱执行保证。
