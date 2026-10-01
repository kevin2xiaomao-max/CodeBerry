# CodeBerry 4.0.3 Implementation Plan

> 审计基线：`codeberry-lite-v4` @ `a562015`（4.0.2）
> 真实问题来源：「你的小掌柜 iOS V3.6」（本地只读参考 `~/workspace/xzg-v361`，`feature/v3.6.1-reference-home`）
> 审计方式：只读。未修改任何仓库文件。
> 目标：不再"见一个 Unknown 硬编码补一个"，做结构性修复。
> 版本：Marketing 4.0.3 / Build 403。
>
> **2026-10-02 用户审核决议（已应用到本计划）**：
> 1. 接受脱敏精简 V3.6 acceptance fixture（`PreviewFixtures/V36Acceptance/`）。
> 2. SwiftData **不做无条件"红→黄"**：可由 Fixture/Mock/preview default 安全替代时 → Warning / NeedsMock；无法替代且导致目标 View 无法形成有意义 Preview 时 → 仍为 Error（条件逻辑，见 P0-E 修订）。
> 3. 同意预留 `NativePreviewService` 接口和 ADR；4.0.3 不接 axe/swiftui-render，不实现 Mac Service。
> 4. 新增 P0-F～P0-J（见 §8），纳入 4.0.3 Release Gate；执行顺序 S1→S7 + S8～S12。
> 5. 真实 V3.6 Release Acceptance 加强：`XZG_REFERENCE_ROOT` 必填，真实树再跑完整 acceptance；Synthetic CI Acceptance 与 Real V3.6 Acceptance 分开报告。

---

## 1. 解析链现状图

identifier 从源码到"未知标识符"判决的完整路径（4.0.2 现状）：

```
源码 ──► PreviewEngine.parseTree() ──► PreviewDocument
                                          ├─ views: [String: PreviewViewStruct]
                                          │    └─ viewStruct(from:)  ← ★ P0-A 断点
                                          │         ├─ body → bodyStatements
                                          │         ├─ var xxx: some View → computedViews   (PreviewComputedView)
                                          │         ├─ func xxx() -> some View → functions    (PreviewFunction)
                                          │         ├─ @State/let/var(无 accessor) → properties (PreviewProperty)
                                          │         └─ var xxx: String { get } 等普通计算属性 → ✂ 直接丢弃，无任何记录
                                          └─ types: [String: PreviewTypeInfo]  (4.0.2 P0-3 新增)
                                               └─ extractTypes(): class/struct/enum/actor
                                                    ├─ static let 字面量 → staticValues
                                                    ├─ 非字面量 static → opaqueStatics
                                                    └─ 实例 var/let → instanceMembers: [name: 类型注解]

──► PreviewProjectIndex（项目级）
     ├─ viewsByName: [String: (file, PreviewViewStruct)]   ← 跨文件 View
     ├─ tokensByName: [String: PreviewToken]               ← 设计 token
     └─ typesByName: [String: PreviewTypeInfo]            ← 跨文件普通类型
     索引机制：ProjectIndexPolicy.maxFiles=1000；冷启动后台增量、
     mtime/size 预过滤、可取消；当前文件优先。

──► PreviewCanvasView.recompute()
     └─ IncrementalPreview.evaluate(..., projectIndex: hasProjectContext ? projectIndex : nil, ...)
          └─ evaluator.projectIndex = projectIndex        (IncrementalPreview.swift:85)

──► PreviewEvaluator.eval() 求值
     ├─ evalReference(name)  (PreviewEvaluator.swift:360-388)  ← ★ 判决点 A（唯一 .error diagUnknownIdentifier 发射处，全仓仅此一处）
     │    顺序：$binding → env.locals → env.stateKeys/runtime → computedViews[env.typeName]
     │          → projectIndex.tokensByName → mockStore → activeTypes → ✖ .error 未知标识符
     ├─ evalMember(member)   (PreviewEvaluator.swift:~410-460) ← ★ 判决点 B
     │    顺序：Color/Font/Double/CGFloat/Float 硬编码表 → activeTypes[base]
     │          (staticValues → opaqueStatics → enum case 当 .member) 
     │          → tokensByName[qualified] → mockStore[qualified]
     │          → eval(base) 递归 → 落到判决点 A
     │    注意：Calendar/Date 等 Foundation 类型在此处没有任何分支，直接掉进递归
     └─ evalCall(call)       (PreviewEvaluator+Calls.swift:10-…)
          └─ 工厂函数/自定义 View 实例化；ComponentRegistry.evaluateCustom 兜底

──► 诊断面板 ← evaluator.diagnostics（PreviewDiagnosticSeverity: error/warning/info/needsMock/ignored）
──► Readiness 面板 ← PreviewReadiness.report(of:in:knownViews:)
     └─ knownViews = Set(projectIndex.viewsByName.keys)   (PreviewCanvasView.swift:605-606)
        "缺少自定义组件支持" = 调用点名 ∉ (ComponentRegistry.isKnownView ∪ knownViews ∪ nonViewCallNames)
        nonViewCallNames (PreviewReadiness.swift:143-170) 已含 Calendar/Date/Locale/Array/Binding…
        → Readiness 侧 4.0.2 已修好；残留 Unknown 全部来自 evaluator 诊断面板
```

**核心结论**：当前有"三个半" truth source，各自判断一遍 ——
`PreviewViewStruct`（当前文件 View 语义）、`PreviewProjectIndex`（跨文件）、`ComponentRegistry`（built-in）、`PreviewReadiness.nonViewCallNames`（半个：只管 Readiness 面板，不管 evaluator）。
`evalReference` 是事实上的解析器，但它的 7 层顺序是硬编码在函数里的，没有统一的 SymbolResolver 接口，Preview / Readiness / Diagnostics 无法共用同一判决。

---

## 2. 六个 identifier 的逐个 root cause（带代码证据）

真实声明位置（`~/workspace/xzg-v361` 实测）：

| identifier | 真实声明 |
|---|---|
| `DemoMode` | `XiaoZhangGui/Demo/DemoMode.swift`：`@Observable @MainActor final class DemoMode`，`static let shared`，实例 `isEnabled: Bool` / `sessionID: UUID` |
| `greetingPrefix` | `HomeView.swift:189`：`private var greetingPrefix: String { … }`（普通计算属性） |
| `V32` | `DesignSystem/V32/V32Color.swift`：`enum V32`，`@MainActor static var pageBG: Color { … }` 等 |
| `ownerDisplayName` | `HomeView.swift:197`：`private var ownerDisplayName: String { … }`（普通计算属性） |
| `handlingItems` | `HomeView.swift:43`：`private var handlingItems: [HomeInboxItem] { … }`（普通计算属性） |
| `Calendar` | Foundation 类型；`HomeView.swift:190` 用 `Calendar.current.component(.hour, from: Date())` |

### 2.1 greetingPrefix / ownerDisplayName / handlingItems —— 解析期被丢弃（P0-A）

**证据**：`PreviewEngine.swift:366-371`（`viewStruct(from:)`）：

```swift
} else if binding.typeAnnotation?.type.trimmedDescription.contains("some View") == true,
          let statements = Self.getterStatements(binding.accessorBlock) {
    computedViews[name] = PreviewComputedView(...)   // 只收 some View
} else if binding.accessorBlock == nil {
    properties.append(...)                            // 只收无 accessor 的存储属性
}
// 有 accessorBlock 但类型不是 some View → 两个分支都不进，静默丢弃
```

`greetingPrefix: String { … }` 有 getter 但类型是 `String` → **在 parse 阶段就被丢掉**，`PreviewViewStruct` 里没有任何记录。
求值时 `evalReference`（`PreviewEvaluator.swift:360-388`）：locals 无 → stateKeys 无 → `computedViews` 无（只有 View）→ tokens 无 → mock 无 → `activeTypes` 无 → **L387 `diagnose(.error, .diagUnknownIdentifier)`**。

一句话：**普通计算属性在 `viewStruct(from:)` 被静默丢弃，求值期无任何层能认出它，只能报 Error。**

### 2.2 Calendar —— 全链无 Foundation 层（P0-D）

**证据**：`PreviewEvaluator.swift` `evalMember`（~L415-420）：base 为 `DeclReferenceExpr("Calendar")` 时，switch 只处理 `Color` / `Font` / `Double|CGFloat|Float` 三组硬编码；`activeTypes["Calendar"]` 为 nil（没有任何文件声明名为 Calendar 的类型）；`tokensByName` / `mockStore` 无；于是 `eval(base)` 递归进 `evalReference("Calendar")` → L387 `.error`。

全仓没有任何"known system symbol"层。`PreviewReadiness.nonViewCallNames`（`PreviewReadiness.swift:143-170`）虽然列了 Calendar/Date/Locale 等，但**只服务于 Readiness 面板**，evaluator 完全看不到它 —— 这就是"Analyzer 认识但 Evaluator 不认识"的实例。

一句话：**Foundation 类型在 evaluator 侧零覆盖，`Calendar.current` 必走 error 路径。**

### 2.3 DemoMode —— 代码路径存在，但从未被真实验证过 ⚠️

按 4.0.2 代码，`DemoMode` **应该**能解析：
- `extractTypes`（`PreviewEngine.swift:~290`）能处理 `@Observable @MainActor final class DemoMode`（attribute 不影响 `as(ClassDeclSyntax.self)`）；`static let shared = DemoMode()` → probe 求值失败 → `opaqueStatics`；`isEnabled: Bool` → `instanceMembers`。
- `evalReference("DemoMode")` → `activeTypes["DemoMode"]` 命中 → L383-386 报 `.info`（"使用预览默认值"）+ `.typeStub`，**不是 error**。
- `DemoMode.shared.isEnabled` → `evalMember` L430-437 → typeStub → `instanceMembers["isEnabled"]="Bool"` → previewDefault。

但真机仍报 Unknown（`.error` 文案"未知标识符"，与 `.info` 的"使用预览默认值"文案不同 —— `Support/L10n.swift:581/594`），说明设备上求值时 `activeTypes["DemoMode"] == nil`。

**证据链（为什么这是"未验证"而非"已修好"）**：
- 唯一覆盖真实树的测试 `XiaoZhangGuiRealProjectIndexTests`（`testRealTreeIndexResolvesDemoModeType`）在 CI 上因 checkout 缺失而 `XCTSkip` —— 277 tests 中的 12 个 skip 包含它。**这个断言从未在任何地方真正跑通过。**
- 本地 `~/workspace/xzg-v361` 有 159 个 Swift 文件（`XiaoZhangGui/` 下），远低于 1000 上限，理论上 `Demo/DemoMode.swift` 应被索引。

**候选断点**（4.0.3 执行阶段必须逐个证实/证伪，不许猜）：
1. 设备上 GitHub Direct 导入的 projectRoot 下是否真实包含 `Demo/` 目录（下载不全？目录被 skip？）。
2. `rebuildInBackground` 冷启动被 `.task(id: source)` 取消后 `indexBuilt` 保持 false → 下一次 warm `update()` 只处理变更文件，**被取消时未完成的文件是否永久遗漏**（`parseInBackground` 合并的是 partial，但 snapshot 阶段 `fileMeta` 预过滤可能让下一次 warm 直接跳过）。
3. `Parser.parse` 对 `DemoMode.swift` 报 `hasError`（SwiftParser 版本与源码语法差）→ `parseFile` 返回 nil → 保留旧条目（冷启动时即无条目）。
4. 同名 symbol：`rebuildLookup()` 按 `files.keys.sorted()` 顺序，后者覆盖前者 —— 若存在同名 `DemoMode` 声明会被静默覆盖（`types[name] = info`）。

一句话：**4.0.2 声称支持 DemoMode，但唯一的真实树验证在 CI 上是 skip，设备行为证明链条某处断了；必须先让真实树测试真正跑起来，再定位断点。**

### 2.4 V32 —— 同 DemoMode，未验证 + 求值语义弱

`enum V32` 的 `@MainActor static var pageBG: Color { … }` 在 `extractTypes` 中因无 initializer（computed var）→ 全部进 `opaqueStatics`；`evalMember("V32.textSecondary")` → L433-436 `kind == .enum` → 返回 `.member("textSecondary")`（渲染成字面 ".textSecondary" 文本，非 error 但视觉错误）。
若设备报 Unknown（error），则 `activeTypes["V32"] == nil`，断点候选同 2.3。

一句话：**V32 的索引与求值路径与 DemoMode 同源问题；即使索引命中，enum opaque static 也只能渲染成 `.member` 占位，语义偏弱。**

### 2.5 小结：断点分布

| identifier | 断点位置 | 性质 |
|---|---|---|
| greetingPrefix / ownerDisplayName / handlingItems | `viewStruct(from:)` 解析期丢弃 → `evalReference` L387 | 确定性代码缺陷 |
| Calendar | evaluator 全链无 Foundation 层 | 确定性代码缺陷 |
| DemoMode / V32 | 索引→传递链某处（待实证）；真实树测试 CI skip 从未验证 | 未验证的声称，需实证定位 |

---

## 3. P0-A → P0-E 结构性修复设计

### P0-A：PreviewComputedProperty 语义模型

**新增** `PreviewEngine.swift`（或新文件 `Preview/PreviewComputedProperty.swift`）：

```swift
struct PreviewComputedProperty {
    let name: String
    let returnType: String                 // "String" / "[HomeInboxItem]" / "Bool" …
    let getterStatements: CodeBlockItemListSyntax?
    var isPureValue: Bool                  // 是否安全纯值（见下）
}
struct PreviewViewStruct {
    …
    /// 普通计算属性（var xxx: T { … }，T 非 View），不含 body。
    var computedProperties: [String: PreviewComputedProperty] = [:]
}
```

`viewStruct(from:)` 修改（`PreviewEngine.swift:366-371`）：第三分支改为
`else if let statements = Self.getterStatements(binding.accessorBlock)` → 收录所有带 getter 的非 View 计算属性（排除 `body`）。

**求值边界**（`PreviewEvaluator.invokeComputedProperty`，仿 `invokeComputedView`，depth 40 保护）：
- 能算：字面量、字符串插值、`if/else` 纯分支、三元、数值/布尔运算、`.count/.isEmpty`、已解析的同级 computed property（递归 depth 保护）。
  - `greetingPrefix`（`Calendar.current.component` → P0-D 近似为当前 hour → 返回"晚上好"等）可完整求值。
  - `handlingItems`（`[HomeInboxItem]` 过滤逻辑）→ 数组求值，元素为 typeStub 时保留结构。
- 必须 NeedsMock：getter 读了 `settings`（外部依赖）、`@Query`、repository、网络、UserDefaults 写入（`ownerDisplayName` 读 `settings.ownerName` → settings 本身 NeedsMock，属性降级为 preview default + NeedsMock 诊断）。
- 安全规则：getter 内出现赋值给外部状态、`try!`、已知副作用 API → 不执行，返回 `previewDefault(forTypeName:)` + `.needsMock`。

**文件**：`Preview/PreviewComputedProperty.swift`（新）、`Preview/PreviewEngine.swift`（`viewStruct(from:)` + `getterStatements` 复用）、`Preview/PreviewEvaluator.swift`（`evalReference` 在 `computedViews` 之后加 `computedProperties` 分支、`invokeComputedProperty`）。

### P0-B：统一 SymbolResolver（12 层）

**新增** `Preview/PreviewSymbolResolver.swift`：

```swift
/// 统一符号解析：Preview / Readiness / Diagnostics 共用同一 truth source。
struct PreviewSymbolResolver {
    enum Outcome {
        case value(PreviewValue)          // 直接可求值
        case needsMock(String)            // 需要数据（属性名/原因）
        case previewDefault(String)       // 安全降级（原因）
        case approximate(String)          // 近似渲染（原因）
        case unresolved                   // 真正无法解析 → 由调用方定级
    }
    // 12 层（按优先级）：
    //  1 local（env.locals）            2 state/binding（env.stateKeys/runtime）
    //  3 stored property（initialValue） 4 computed property（P0-A）
    //  5 computed View                   6 helper function
    //  7 当前文件 type/symbol（doc.types/views）
    //  8 ProjectIndex 跨文件（viewsByName/typesByName/tokensByName，当前文件优先）
    //  9 design token / namespace（V32.xxx 限定查找）
    // 10 Foundation/System known type（P0-D registry）
    // 11 mock/fixture（mockStore / MockCenter）
    // 12 unresolved → 结构化诊断（带候选建议，如"是否指 DemoMode.shared？"）
    func resolve(_ name: String, in env: PreviewEvaluator.Env) -> Outcome
    func resolveMember(base: String, member: String) -> Outcome
}
```

**调用方改造**（分步，每步独立可验证）：
1. `evalReference` 改为调 `resolver.resolve`，按 Outcome 映射到现有 `PreviewValue` + 诊断（行为先保持一致，测试锁死）。
2. `evalMember` 的 base 解析改用 `resolveMember`。
3. `PreviewReadiness.report` 的"missingComponentSupport"判定改用同一 resolver（删 `nonViewCallNames` 硬编码表，改由 P0-D registry 判定；保留测试）。
4. Diagnostics 的定级（P0-E）由 Outcome 直接给出 severity，消除各处自行 `diagnose` 的分级漂移。

**不一次性重写**：resolver 先作为薄封装（内部复用现有 7 层顺序），277 tests 全程绿；再逐层加 P0-A/P0-D 能力。

**文件**：`Preview/PreviewSymbolResolver.swift`（新）、`Preview/PreviewEvaluator.swift`（`evalReference`/`evalMember` 改调 resolver）、`Preview/PreviewReadiness.swift`（判定改调 resolver）、`Preview/PreviewDiagnostics.swift`（Outcome→severity 映射表）。

### P0-C：跨文件 symbol/type 修复

基于 §2.3/2.4 的实证结果修（执行阶段第一步就是让真实树测试真正跑起来，见 §4）：

1. **让 `XiaoZhangGuiRealProjectIndexTests` 在 CI 真正执行**：把测试语料从"依赖外部 checkout"改为"仓库内精简 fixture + 可选真实树"。具体：从 `xzg-v361` 提取 HomeView 依赖闭包的**脱敏精简版**（保留 DemoMode/V32/greetingPrefix 等结构，删业务代码）作为 `PreviewFixtures/` 下的 fixture，CI 必跑；保留 `XZG_REFERENCE_ROOT` 覆盖真实树的本地模式。
2. **索引可观测性**：`rebuildLookup()` 记录覆盖冲突（同名 symbol 来自多个文件 → `.warning` 诊断，列出文件）；`updateIndex` 完成后记录 `indexedCount/totalCount`，供 acceptance 断言。
3. **取消后收敛**：warm `update()` 必须能补上冷启动被取消时未合并的文件（审计发现 `fileMeta` 预过滤可能让 warm 跳过未索引文件 —— 执行阶段写测试证实/证伪后修）。
4. **命名空间**：`V32.xxx` 先查 `typesByName["V32"]` 再查 `tokensByName["V32.xxx"]`（P0-B 第 9 层）；enum opaque static 渲染从 `.member` 文本改为带 token 色值的近似（若静态求值失败则 placeholder + Info）。

**文件**：`Preview/PreviewProjectIndex.swift`（冲突记录、取消收敛）、`Preview/PreviewSymbolResolver.swift`（第 9 层）、`PreviewFixtures/`（新 fixture 语料）。

### P0-D：Foundation/System Registry

**新增** `Preview/PreviewSystemRegistry.swift`：

```swift
enum PreviewSystemRegistry {
    /// 已知系统类型 → 成员近似策略
    static func member(of type: String, name: String) -> PreviewValue?
    // 第一批：Calendar / Date / Locale / TimeZone / UUID / URL / DateComponents
}
```

**求值边界**：
- 安全近似（纯值、无副作用）：`Calendar.current` → 预置一个 `PreviewValue.system("Calendar")`；`.component(.hour, from: Date())` → 用真机当前时间近似（Info 标注"使用当前时间近似"）；`Date()` → 当前时间字符串；`UUID()` → 固定占位 UUID（ deterministic，避免每次渲染抖动）；`Locale.current` → `"zh_CN"`。
- preview default：不能安全执行的 API → `.needsMock` 或 `.info`，**绝不 `.error`**。
- `evalMember` 的 switch 增加 `case "Calendar", "Date", "Locale", "TimeZone", "UUID", "URL", "DateComponents"` 分支，查 registry。
- P0-B 第 10 层即此 registry；Readiness 的 `nonViewCallNames` 表改为由 registry 生成（单源）。

**文件**：`Preview/PreviewSystemRegistry.swift`（新）、`Preview/PreviewEvaluator.swift`（`evalMember` 接 registry）、`Preview/PreviewReadiness.swift`（删硬编码表）。

### P0-E：Diagnostics 分级

**严格定义**（`PreviewDiagnostics.swift` 补充文档 + 映射表）：

| Severity | 定义 | 示例 |
|---|---|---|
| Error | 真正无法继续解析；继续渲染会产生误导 | 语法错误、evaluator fatal、12 层全灭的 truly unknown |
| Warning | 可降级但结果可能不完整 | 近似渲染、opaque static 占位、类型擦除 |
| NeedsMock | 需要数据才能完整 | @Query 数组、settings、repository、Environment 缺失 |
| Info | 使用了 preview default / external package / 近似 | DemoMode stub、Calendar 时间近似、Charts 跳过 |

**重新定级清单**（执行阶段逐条改）：
- `evalReference` L387 未知标识符：保持 Error，但文案追加"12 层均未命中" + 同名候选建议（减少误报体感）。
- `DemoMode` 类 bare 引用：已是 Info，保持。
- SwiftData（`import SwiftData` / `@Model` / `@Query`）：**条件降级**（用户决议，不一刀切）——
  - 可由 Fixture/Mock/preview default 安全替代时（@Query → fixture arrays、modelContext 标记"预览不执行"）：→ Warning / NeedsMock；
  - 无法替代且导致目标 View 无法形成有意义 Preview 时（例如 View 的 body 强依赖真实 @Query 结果做分支且无 fixture）：→ 仍为 Error。
  - 实现为 `SwiftDataSubstitutionPolicy`：先尝试 substitution（fixture/mock/default），成功则降级，失败则保持 Error 并说明"无可用替代"。
- Charts 等 external package：已是 Warning（`externalPackageNotExecuted` 🟡），保持；evaluator 内跳过 Charts 相关调用时用 Info 而非 Warning（减少噪音）。
- `Calendar.current.component` 近似：Info。
- 近似渲染的 built-in（GroupBox/LazyVGrid 等）：Warning → 改为 Info（"已近似渲染"不值得黄）。

**文件**：`Preview/PreviewDiagnostics.swift`（分级定义文档化）、`Preview/PreviewEvaluator.swift`（各 `diagnose` 点重定级）、`Preview/PreviewReadiness.swift`（`unsupportedRuntime` 降级）。

### 分步计划（每步独立可验证，先后顺序）

1. **S1 可观测 + 真实树测试转正**：fixture 语料 + 索引冲突/计数可观测 + 真实树测试 CI 必跑。验证：新测试绿；旧 277 绿。
2. **S2 P0-D SystemRegistry**：evaluator 接 registry；Calendar/Date 等不再 error。验证：`PreviewSystemRegistryTests` + HomeView greetingPrefix 可求值。
3. **S3 P0-A ComputedProperty**：parse 收录 + `invokeComputedProperty` + 求值边界。验证：`PreviewComputedPropertyTests`（greetingPrefix/ownerDisplayName/handlingItems 真实 getter）。
4. **S4 P0-B Resolver 薄封装**：12 层接口落地，内部先复用现有顺序；调用方逐个切换（evaluator → readiness → diagnostics）。验证：每切换一个，277 全绿。
5. **S5 P0-C 跨文件实证修复**：基于 S1 的真实树测试定位 DemoMode/V32 断点并修；命名空间层；取消收敛。验证：6 identifier 验收红线。
6. **S6 P0-E 重定级**：按清单逐条改 severity（含 SwiftData 条件降级逻辑）。验证：`PreviewDiagnosticsSeverityTests`（每个诊断点的期望级别锁死）。
7. **S7 P1 acceptance + P2 接口预留**：harness + ADR（见 §4/§6）。
8. **S8 P0-F Selected Preview Identity**：`PreviewCandidate.viewName` 端到端传递（Candidate → PreviewCanvas → IncrementalPreview → PreviewEvaluator → `renderRoot(targetView:)`），删除 `viewOrder.first` 默认。验证：多 View 单文件测试（选 HomeView → root 为 HomeView；选子 View → root 为子 View）。
9. **S9 P0-G Cache Invalidation**：cache fingerprint 纳入 6 维（source revision / targetViewName / ProjectIndex generation / Mock+Profile revision / Runtime state revision / Fixture revision）；5 个 stale 回归测试。验证：改依赖文件/Mock/Profile/runtime/fixture 均触发重新 evaluate，禁止 stale。
10. **S10 P0-H Generated Source Isolation**：source-role policy（production/generatedFixture/acceptanceFixture/test/debugPrototype）；Page Discovery 与可预览列表过滤非 production；generated 不得覆盖 production 同名 symbol。验证：HomeViewFixture 不再作为第二个 Production View 出现。
11. **S11 P0-I Unified ProjectFilePolicy**：Analyzer/Index/Page Discovery 共用同一 policy（max file / source roots / excluded dirs / generated policy / 分类）。验证：三处对同一 fixture 树的文件集合判定一致；`.git/.build/Pods/…` 排除测试。
12. **S12 P0-J Single Fixture Pipeline**：审计删除旧 `header + original source → write fixture` 路径；所有入口统一经 `PreviewFixtureGenerator → plan → validate → generate → register`。验证：parity test（不同 UI entry 生成同一 HomeView fixture 语义一致）。

---

## 4. 测试方案

### 新增 regression tests

| 测试文件 | 覆盖 |
|---|---|
| `PreviewComputedPropertyTests` | String/Bool/Int/Double/Array/Optional/Date getter 求值；副作用 getter → NeedsMock；`greetingPrefix` 真实逻辑 |
| `PreviewSymbolResolverTests` | 12 层优先级（local 覆盖 index、index 覆盖 mock 等）；unresolved 带候选建议 |
| `PreviewSystemRegistryTests` | Calendar/Date/Locale/TimeZone/UUID/URL/DateComponents 近似边界；deterministic（UUID 固定） |
| `PreviewDiagnosticsSeverityTests` | 每个诊断点的期望 severity 锁死（防回退；含 SwiftData 条件降级两条路径） |
| `PreviewCrossFileNamespaceTests` | `V32.xxx` 限定查找；同名 symbol 冲突诊断 |
| `PreviewSelectedIdentityTests`（P0-F） | 单文件多 View：选 HomeView → root 为 HomeView；选子 View → root 为子 View；禁止 `viewOrder.first` 默认 |
| `PreviewCacheInvalidationTests`（P0-G） | 5 个 stale 回归：改依赖文件 / 改 Mock value / 切换 Mock Profile / Runtime state 变 / Fixture 变 → 必须重新 evaluate |
| `GeneratedSourceIsolationTests`（P0-H） | HomeViewFixture/HomeActionRowFixture 不得作为 Production 页面出现；不得覆盖 production 同名 symbol |
| `ProjectFilePolicyTests`（P0-I） | Analyzer/Index/Page Discovery 对同一树的文件集合判定一致；`.git/.build/Pods/DerivedData/.swiftpm/Carthage/node_modules/fastlane` 排除 |
| `FixturePipelineParityTests`（P0-J） | 不同 UI entry 生成同一 HomeView fixture → 语义一致；旧 `header+source→write` 路径已删除 |
| `XiaoZhangGuiAcceptanceTests`（P1 harness） | 见下 |

### 现有 277 tests 保护策略

- S1–S7 每步完成后全量跑（CI）；任何一步红了就地修，不攒。
- 红线延续：不删测试、不降断言、不跳过失败项、不改测试迎合实现。
- `nonViewCallNames` 删除时，其对应的 `PreviewReadinessClassificationTests` 用例必须平移到 registry 测试（行为保留）。

### P1 V3.6 acceptance harness 设计（加强版：Synthetic CI Acceptance + Real V3.6 Acceptance 分开）

`XiaoZhangGuiAcceptanceTests`（Linux 可跑的静态分析路径，不依赖 Xcode）：

- **语料**：`PreviewFixtures/V36Acceptance/` —— 从 `xzg-v361` 提取的脱敏精简语料，覆盖 HomeView / TodoView / CalendarView / PerformanceView / CustomerView / ExpiryView / MemoView / ProfileView 及其直接依赖（DemoMode、V32、V35/V36 组件骨架）。保留原始标识符与类型结构，删业务实现。CI 必跑。
- **流程**：`PreviewProjectIndex.update()` 建索引（计时：首次 index 时间）→ 改一个文件 → 增量 `update()`（计时：二次增量时间）→ 对每个目标 View 跑 `IncrementalPreview.evaluate` → 收集诊断。
- **输出 Before/After**：Error 数 / Warning 数 / NeedsMock 数 / 成功解析自定义 View 数 / placeholder 数 / 是否 crash / 首次 index 时间 / 二次增量 index 时间。以 4.0.2（`a562015`）为 Before 基线。
- **验收红线**：DemoMode / greetingPrefix / V32 / ownerDisplayName / handlingItems / Calendar 不得为 `.error` 未知标识符。
- **防作弊机制**：
  1. `unresolved` 计数器独立统计（resolver 第 12 层命中数），Before/After 对比必须同时下降 Error 数**和** unresolved 数 —— 只降 Error 不降 unresolved 视为作弊。
  2. 对 6 个红线 identifier 做**值断言**而非仅"无 error"：如 `greetingPrefix` 求值结果必须是非空 String 且符合时间段逻辑；`DemoMode.shared.isEnabled` 必须为 Bool。
  3. 随机抽查：harness 额外抽 20 个非红线 identifier，人工（审计时）确认其定级合理。

### Real V3.6 Acceptance（Release Gate 必需，不 optional）

4.0.3 Release 前必须在**当前真实 XiaoZhangGui V3.6 tree**上再跑一次完整 acceptance：

- `XZG_REFERENCE_ROOT` **不能是 optional**：harness 要求环境变量指向真实树（本地 `~/workspace/xzg-v361`，只读）；缺失则 acceptance 显式失败，不许静默跳过。
- 特别验证真实 HomeView：
  - target root == HomeView（P0-F：选 HomeView 必须以 HomeView 为 root）
  - DemoMode resolved / greetingPrefix resolved / V32 resolved
  - ownerDisplayName resolved/default/NeedsMock 合理
  - handlingItems resolved / Calendar resolved/approximate
  - 主要 V35/V36 components resolved
  - generated fixture 不污染 production list（P0-H）
  - 修改跨文件 dependency 后 cache 正确失效（P0-G）
- 最终报告**分别列** `Synthetic CI Acceptance` 与 `Real V3.6 Acceptance`，**禁止把两者混成一个 PASS**。
- 截图：若自动环境可取得真实 HomeView Preview 截图则附上；否则明确标记"**真机视觉仍待最终验收**"，不许虚报。

### Linux 无 Xcode 的验证边界

- 可跑：全部单元测试、索引/解析/求值逻辑、acceptance harness（静态分析路径）。
- 不可跑：真机渲染手感、`#Preview` 真实渲染对比、Simulator 截图。
- 留给用户真机验证：4.0.3 IPA 装机后打开 XiaoZhangGui HomeView，确认 6 identifier 无红、视觉主体正常。harness 输出作为"实验室证据"，真机作为"最终验收"，两者缺一不可，如实写入报告。

---

## 5. P1-B 回归保留清单

4.0.2 已完成、4.0.3 不得退化（每项有对应测试锁死）：

- 1000-file index（`ProjectIndexPolicy`，`PreviewLargeProjectIndexTests`）
- cancellation（后台索引可取消、`rebuildInBackground`）
- fixture（`PreviewFixtureGenerator`，`PreviewFixtureSwiftDataTests`、`XiaoZhangGuiHomePreviewFixtureTests`）
- Mock Center（type-aware，`PreviewMockTypeAwareTests`）
- Charts external handling（`externalPackageNotExecuted`，P1-8）
- streaming SHA256（`ArchiveExtractor`，`StreamingHashTests`）
- sync/conflict safety（`WorkspaceSync` partial-base，`WorkspaceSyncTests`）
- 4.0.1 的全部修复（WorkspaceTitleMenu、Changes 接线、Preview→Code 切 tab —— `WorkspaceNavigationTests`、`WorkspaceFlowUITests`）

---

## 6. P2 Native Preview 研究结论 + ADR 草案 + 预留接口

### 研究结论

**k-kohey/axe**（https://github.com/k-kohey/axe）：
- SwiftUI Preview 命令行工具 + VS Code 扩展 + 热重载。`axe preview <file>` 在**无头 iOS Simulator** 上启动真实 SwiftUI preview，截图输出 PNG；`preview serve` 提供 JSON Lines 协议的 IDE 后端；`preview watch` 热重载。
- 原理：需要真实 Xcode 项目（`.axerc` 配 `PROJECT`/`SCHEME`），走 xcodebuild 构建，在 Simulator 里跑真 SwiftUI。
- 一句话：**最高保真（真编译+真 Simulator），但最重** —— 需要 Mac 上有完整 Xcode 项目、Simulator 启动时间、构建时间。

**olliewagner/swiftui-render**（https://github.com/olliewagner/swiftui-render）：
- 无头 SwiftUI 渲染 CLI，**不需要 Xcode 项目和 Simulator**。`swiftui-render MyView.swift --iphone -o out.png` 即时出图。
- 原理：swiftc 即时编译单文件并链接 SwiftUI；三后端：ImageRenderer（纯 AppKit，最快）、AppHost（NSWindow+NSHostingView）、Catalyst（Mac Catalyst app，iOS 渲染最准）。
- 要求：macOS 13+、Xcode Command Line Tools、Apple Silicon。
- 一句话：**最轻（单文件即时编译），但只擅长孤立单 View** —— 真实项目文件的跨文件依赖需要服务侧合成可编译模块。

### ADR 草案（ADR-001：Native Preview 双轨）

- **决策**：保留 Lite Preview（iPhone 端即时、离线、零依赖）为主路径；新增 Native Preview 为可选增强通道，架构为：
  `iPhone CodeBerry → Mac Preview Service →（swiftui-render 快通道 / axe+Simulator 全量通道）→ PNG frame + diagnostics → iPhone`
- **通道选择**：单文件/组件级预览走 swiftui-render（快，秒级）；整页/整项目级保真验证走 axe（慢，分钟级，需 Xcode 项目）。Mac 服务侧负责：接收源码 bundle → 合成可编译预览模块（注入 Preview wrapper + fixture）→ 选通道渲染 → 回传 PNG + 编译诊断。
- **为什么不直接二选一**：axe 保真但重（Simulator 启动+构建，手机端等待体验差）；swiftui-render 轻但需要服务侧做"多文件合成单模块"的工作。双通道互补。
- **本轮不做的**：不引入 axe / swiftui-render 依赖，不写 Mac 服务，不重写 Preview，不在 iOS 端加 Mac 强依赖。

### 本轮预留接口清单（只定义协议/扩展点，不实现）

```swift
/// Native Preview 渲染请求（P2 预留，4.0.3 只定义不实现）
struct NativePreviewRequest: Codable, Sendable {
    let files: [String: String]      // path → source（项目 bundle）
    let targetView: String
    let device: String               // "iphone15" 等
    let colorScheme: String
    let fixture: [String: String]?   // mock/fixture 注入
}
struct NativePreviewResponse: Codable, Sendable {
    let pngData: Data?
    let diagnostics: [String]        // 编译期诊断原文
    let channel: String              // "swiftui-render" | "axe"
}
protocol NativePreviewService {
    func render(_ request: NativePreviewRequest) async throws -> NativePreviewResponse
}
/// Lite Preview 侧扩展点：PreviewEngine 输出的 IR（view node + diagnostics）
/// 未来可序列化为 NativePreviewRequest.files —— 本轮只保证 IR 可 Codable，不接线。
```

**文件**：`Preview/NativePreviewService.swift`（仅协议+数据结构，无实现）、`docs/ADR-001-native-preview.md`。

---

## 7. 风险

### 技术风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| `invokeComputedProperty` 求值引入副作用（getter 内写 UserDefaults/调 repository） | 高 | 白名单纯值表达式；副作用模式 → NeedsMock 不执行；depth 40 + 求值步数上限 |
| 统一 resolver 切换调用方时行为漂移（277 tests 保护网有洞） | 中 | S4 分步切换，每步全量测试；新增 `PreviewSymbolResolverTests` 锁 12 层优先级 |
| 真实树测试转正后暴露索引深层 bug（如取消收敛），修起来超预期 | 中 | S1 优先做，风险前置；修不好则降级为"已知限制+诊断提示"如实报告 |
| `Calendar.current.component` 用真机时间近似 → 同一 preview 多次渲染结果不一致（早/中/晚问候语跳变） | 低 | 近似值缓存到本次 preview 会话；Info 标注 |
| SwiftParser 版本与 V3.6 源码语法差导致整文件 hasError | 低 | 已验证 HomeView 可 parse；acceptance 覆盖 8 个 View，任一失败即暴露 |

### 工期风险

- 按 4.0.2 节奏（5 轮 CI），S1–S7 约需 4–6 轮 CI（每轮 ~15–20 分钟），总计约 2.5–4 小时。CI 排队是主要变量。
- P0-C 的实证定位可能挖出索引架构级问题 —— 若 S1 发现，立即向用户报告并重新评估 S5 范围，不硬赶。

### Linux 无 Xcode 的验证盲区

- 单元测试与 acceptance harness 只能证明"逻辑正确"，不能证明"真机渲染正确"。
- 最终必须用户用 4.0.3 IPA 在 iPhone 上打开 XiaoZhangGui HomeView 实测（6 identifier + 视觉主体）。这是验收的必要条件，报告中如实列为 Remaining Risk，不虚报。

---

## 8. P0-F～P0-J 新增结构性问题（用户 2026-10-02 追加，纳入 Release Gate）

### P0-F — Selected Preview Identity

**问题**：`PreviewCandidate.viewName` 未端到端传递，某处默认使用 `viewOrder.first`，导致用户选了 HomeView 却渲染了文件里第一个 View。

**修复**：`viewName` 全链传递 —— `PreviewCandidate` → `PreviewCanvas`（recompute）→ `IncrementalPreview.evaluate(targetViewName:)` → `PreviewEvaluator` → `renderRoot(targetView:)`。删除所有 `viewOrder.first` 兜底；若 `viewName` 缺失 → 显式诊断（Warning "未指定目标 View"），不静默选第一个。

**文件**：`Preview/IncrementalPreview.swift`（`evaluate` 签名加 `targetViewName`）、`Preview/PreviewEvaluator.swift`（`renderRoot(targetView:)`）、`Preview/PreviewCanvasView.swift`（传递）、`Workspace/` 中 candidate 构造处。

**测试**：`PreviewSelectedIdentityTests` —— 单文件含多个 View（`MultiView.swift`：`HomeView` + `ChildRow` + `HomeHeader`）；选择 HomeView → `renderRoot` 的 root typeName == "HomeView"；选择 ChildRow → root == "ChildRow"；断言 evaluated root 的类型名，不只断言"无 error"。

### P0-G — Incremental Preview Cache Invalidation

**问题**：当前 cache 只 keyed 当前文件/body，跨文件依赖、Mock、Profile、runtime、fixture 变化后返回 stale Preview。

**修复**：`PreviewCacheKey` / fingerprint 纳入 6 维：
1. `sourceRevision`（目标文件 content hash）
2. `targetViewName`
3. `projectIndexGeneration`（index generation 计数 + 依赖文件的 revision 摘要）
4. `mockRevision`（MockStore revision + 当前 Profile id）
5. `runtimeStateRevision`（env/runtime state 版本）
6. `fixtureRevision`（fixture 注册表版本）

任一维度变化 → cache miss → 重新 evaluate。fingerprint 计算必须便宜（hash 摘要，不重扫）。

**文件**：`Preview/IncrementalPreview.swift`（cache key 结构体重写）、`Preview/PreviewProjectIndex.swift`（暴露 `generation`）、`Preview/PreviewMockStore.swift`（暴露 `revision`）、`Preview/PreviewFixtureRegistry.swift`（暴露 `revision`，若无则新建）。

**测试**：`PreviewCacheInvalidationTests` —— 5 个 regression：
1. HomeView.swift 不变，改 `V36QuickActions.swift`（依赖）→ 必须重新 evaluate（evaluate 计数 +1）；
2. 改 Mock value → 重新 evaluate；
3. 切换 Mock Profile → 重新 evaluate；
4. Runtime state 改变 → 重新 evaluate；
5. Fixture 改变 → 重新 evaluate。
每个用例先 assert 缓存命中（计数不变），再改对应维度 assert 计数 +1。**禁止返回 stale Preview** 是硬断言。

### P0-H — Generated Source Isolation

**问题**：真机已出现 `HomeView — HomeView.swift` / `HomeView — HomeViewFixture.swift` 双条目（`HomeActionRow` / `HomeSparkline` 同样）。Generated fixture 被当成普通 Production 页面列入"可预览页面"，且可能覆盖 production 同名 symbol。

**修复**：建立 `SourceRole` policy：
```swift
enum SourceRole { case production, generatedFixture, acceptanceFixture, test, debugPrototype }
```
- `PreviewFixtureGenerator.generate` 完成后调用 `register(role: .generatedFixture, boundTo: <原 Production View>)`；
- Page Discovery / "可预览页面" 列表只列 `role == .production`；
- Symbol 解析时 generated 不得覆盖 production 同名 symbol（production 优先；generated 同名 → Warning 诊断"被 production 遮蔽"）；
- Generated Fixture 可绑定到原 Production View（`boundTo`），作为其 fixture 数据源，但不能成为第二个 Production View。

**文件**：`Preview/PreviewSourceRole.swift`（新）、`Preview/PreviewFixtureGenerator.swift`（register）、Page Discovery（`ProjectAnalyzer`/`PreviewPageDiscovery` 过滤）、`Preview/PreviewSymbolResolver.swift`（第 8 层加 role 优先级）。

**测试**：`GeneratedSourceIsolationTests` —— fixture 树含 `HomeView.swift`（production）+ `HomeViewFixture.swift`（generated）；断言可预览列表只有 1 个 HomeView；断言 resolver 对 "HomeView" 返回 production；断言 fixture 的 `boundTo == "HomeView"`。

### P0-I — Unified Project File Policy

**问题**：ProjectAnalyzer / PreviewProjectIndex / Preview Page Discovery 各自有一套文件过滤（maxFiles、excluded dirs、generated 分类），出现"Analyzer 看得到、Index 看不到"或"Index 把 generated 当 Production"。

**修复**：三处共用同一个 `ProjectFilePolicy`：
```swift
struct ProjectFilePolicy {
    let maxFiles: Int                 // = ProjectIndexPolicy.maxFiles（单源）
    let includedSourceRoots: [String] // 默认 [""]（项目根）
    let excludedDirectoryNames: Set<String> // .git/.build/Pods/DerivedData/.swiftpm/Carthage/node_modules/fastlane/…
    let generatedSourceNames: Set<String>    // "PreviewFixtures" 等 → role .generatedFixture
    let acceptanceFixtureNames: Set<String> // "V36Acceptance" 等 → role .acceptanceFixture
    let testPathMarkers: Set<String>        // "*Tests.swift"、"Tests/" → role .test
    func role(of path: String) -> SourceRole
    func isIndexed(_ path: String) -> Bool
}
```
- `ProjectIndexPolicy.maxFiles` 并入（P0-I 落地后 `ProjectIndexPolicy` 引用 `ProjectFilePolicy`，不留两套 maxFiles）。
- Analyzer、Index、Page Discovery 构造时注入同一 `ProjectFilePolicy` 实例（`WorkspaceStore` 统一创建）。

**文件**：`Preview/ProjectFilePolicy.swift`（新）、`Preview/ProjectIndexPolicy.swift`（改调）、`ProjectAnalyzer`（注入）、`Preview/PreviewProjectIndex.swift`（注入）、Page Discovery（注入）。

**测试**：`ProjectFilePolicyTests` —— 同一 fixture 树（含 `.git/`、`Pods/`、`PreviewFixtures/`、`XxxTests.swift`），三处（Analyzer/Index/Discovery）返回的文件集合 + role 判定完全一致；`generated` 不得出现在 production 列表。

### P0-J — Single Fixture Pipeline

**问题**：存在多条 fixture 生成路径（旧的 `header + original source → write fixture`），语义不一致。

**修复**：审计并删除/迁移旧路径；所有 fixture 入口统一经过：
```
PreviewFixtureGenerator → plan → validate → generate → register(generated-source role)
```
- 入口清单（执行阶段 grep 确认并逐个迁移）：Canvas "Generate Fixture"、Previewable Pages "Generate Fixture"、Mock Center 相关创建、其他 fixture entry。
- 旧 `header + original source → write fixture` 路径删除；若有调用方，迁移到新 pipeline。
- `plan` 阶段输出 fixture 计划（目标 View、依赖、mock 需求），`validate` 校验（目标 View 存在、role 正确、不覆盖 production），`generate` 生成，`register` 注册 role + boundTo。

**文件**：`Preview/PreviewFixtureGenerator.swift`（pipeline 四阶段；删除旧路径）、各 UI entry 调用点。

**测试**：`FixturePipelineParityTests` —— 从 Canvas entry 和 Previewable Pages entry 分别为同一 HomeView 生成 fixture，断言两者语义一致（plan 内容、generated source、role、boundTo 相同）；断言旧路径符号已不存在（grep 级测试或编译期保证）。

---

## 9. 需要用户决策的产品问题（2026-10-02 已决议）

1. ✅ **语料脱敏方式**：已接受"结构保留、业务删减"的脱敏精简 fixture 进 `PreviewFixtures/V36Acceptance/`。
2. ✅ **SwiftData 分级**：不做无条件"红→黄"，采用条件逻辑（见 P0-E 修订）：可安全替代 → Warning/NeedsMock；无法替代且目标 View 无法形成有意义 Preview → 仍为 Error。
3. ✅ **Native Preview**：同意预留 `NativePreviewService` 接口和 ADR；4.0.3 不接 axe/swiftui-render，不实现 Mac Service。

除上述三项外，无其他产品决策需求；其余按本计划执行。
