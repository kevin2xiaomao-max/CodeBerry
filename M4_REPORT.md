# M4 Report — Git Workspace + Safety

## 完成内容（§35）

True Git 已按 M0 决议 DEFERRED 到 4.1，本里程碑交付 Snapshot Mode + 安全。

### Snapshot Mode
- `SnapshotChanges.swift`：base/current manifest 三路对比 → `[LocalChange]`（added/modified/deleted，按 path 排序）；unified diff patch 导出（LCS 行级 diff，大文件有 250k 上限保护）。
- `ChangesTabView`（M4Views.swift）："更改" tab 内容 —— 本地更改列表、冲突区、导出 Patch、立即同步。M5 接入 4-tab 导航。

### Local History
- `LocalHistory.swift`：每次成功保存自动记录 revision（CryptoKit SHA-256 去重）；每文件上限 50 个、30 天 prune；`LocalHistoryStore.shared`。
- `LocalHistoryView`：按文件浏览历史版本，swipe 恢复。EditorPaneView tabBar 新增历史按钮（clock.arrow.circlepath）+ sheet。

### Conflict UI
- `SyncConflictView` + `ChangesTabView` 冲突区：展示 `GitHubSyncConflict`（bothModified / deleteVsModify），每文件提供 保留本地 / 使用远端 / 手动合并（跳编辑器）。

### Session Restore
- `SessionStore.swift`：UserDefaults 持久化（projectFolder、openFilePath、cursorLines、selectedTab）；`closeProject` 自动保存；`loadSession()` 供 M5 启动恢复。

### Offline
- `OfflineMonitor.swift`：NWPathMonitor 封装，`@Observable`；`OfflineBanner` 在 ContentView 顶部 overlay，离线时橙色胶囊提示。

### Security hardening（§27）
- `SecurityPolicy.swift`：HTTPS-only URL 校验、executable 检测（exec bit + 扩展名）、token redaction（github_pat_/ghp_/gho_）、"绝不执行 repo 内容" 不变量。
- M1 已有：PAT→Keychain、zip slip/path traversal/symlink、max size、temp 清理、archive URL 不持久化——本轮复核无泄漏。

## 测试（4 套件，22 用例）

| 套件 | 用例 | 覆盖 |
|---|---|---|
| LocalHistoryTests | 6 | 记录/去重/排序/隔离/上限/哈希稳定 |
| SnapshotChangesTests | 7 | 三态对比/排序/diff 导出/大文件保护 |
| SessionStoreTests | 4 | 空/回环/更新/清除 |
| SecurityPolicyTests | 5 | HTTPS/exec 检测/redaction/不变量 |

## L10n

新增 20 键（conflict*/history*/change*/exportPatch/syncNow/offlineMessage/done），中英补齐。

## 文件清单

- 新增：Workspace/LocalHistory.swift、SessionStore.swift、OfflineMonitor.swift、SnapshotChanges.swift、SecurityPolicy.swift、M4Views.swift；Tests 4 文件；M4_REPORT.md
- 修改：Workspace/WorkspaceStore.swift（历史 hook、session 方法、closeProject hook）、Editor/EditorPaneView.swift（历史按钮+sheet）、ContentView.swift（OfflineBanner）、Support/L10n.swift（20 键）
