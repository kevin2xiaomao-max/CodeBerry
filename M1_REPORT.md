# M1 Report — GitHub Direct (Snapshot) — CodeBerry Lite 4.0

Date: 2026-10-01
Branch: `codeberry-lite-v4`
Spec: §8 GitHub Direct / §9 同步 / §39 测试 (M1 部分)

## 1. What was built

`CodeBerry/GitHub/` (new, 10 files):

| File | Responsibility |
|---|---|
| `GitHubURLParser.swift` | 三种 URL 形态: repo root / `tree/<ref>[/path]` / `blob/<ref>/<path>`, plus `commit/<sha>` and `git@`/ssh forms |
| `GitHubAuth.swift` | `GitHubAuthProvider` (anonymous / PAT); `GitHubTokenStore` — PAT 只进 Keychain |
| `GitHubClient.swift` | URLSession REST: repo info, branches/tags (paged, capped), ref→SHA resolve, annotated-tag peel, rate-limit mapping |
| `SnapshotDownloader.swift` | zipball 下载: 进度 / 取消 / 重试 (delegate + continuation) |
| `ArchiveExtractor.swift` | ZIPFoundation 安全解压: zip slip / traversal / symlink 拒绝, 500MB/50k 条目上限, `__MACOSX`/`.DS_Store` 跳过, GitHub 顶层目录剥离 |
| `GitHubRepoMetadata.swift` | `.github-repo.json` (dotfile, 导航器隐藏): owner/repo/refKind/refName/baseSnapshotSHA/manifest(path→sha256) |
| `SnapshotSyncEngine.swift` | 导入 (下载→解压→建 manifest) + 三方对比 (base/local/remote) + 应用非冲突变更 |
| `GitHubImportView.swift` | 导入流程 UI: 粘贴 URL → 仓库卡片 → 分支/标签/提交选择 → 进度 → 打开项目 |
| `RepoSyncBar.swift` | 项目页顶部: `owner/repo @ branch (sha)` + 同步按钮 + 状态/冲突提示 |
| `GitHubTokenSettingsView.swift` | 设置页 PAT 管理 (保存/删除, 只进 Keychain) |

Wiring: `ProjectsListView` ("从 GitHub 打开" in the ••• menu) → sheet → import → `openProject` (+ open `/blob/` file when present); `FileNavigatorView` top gets `RepoSyncBar`; `SettingsView` gets the token section; `KeychainStore.delete(key:)` added.

Key design decisions:
- **下载永远按 commit SHA** (`/zipball/<sha>`), 不可变, 避免分支在下载中途移动。
- **冲突未解决绝不覆盖本地**: `threeWayDiff` 是纯函数 — local 改过 + remote 改过 → conflict, 不自动应用; 只有 local 没动的文件才取 remote。
- **斜杠分支名** (`feature/v3.6.1`): URL 解析器朴素切分, `matchBranch` 用分支列表做最长匹配重组。
- 同步前先比对 remote HEAD 与 `baseSnapshotSHA`: 相等则零下载直接返回空 plan。

## 2. Tests (§39 M1 部分)

| Suite | Type | Coverage |
|---|---|---|
| `GitHubURLParserTests` | unit (14) | 3 种 URL + commit/SSH/`.git` 后缀/非法输入/displayRef |
| `ArchiveSecurityTests` | unit (10) | 正常解压+前缀剥离, traversal/absolute/symlink 拒绝, 条目上限, 损坏包, hygiene, sha256 |
| `GitHubClientTests` | unit, mocked transport (10) | DTO 解码, auth 头, 404/401/限流映射, 分支列表, resolve, annotated tag peel, snapshotURL pin SHA |
| `GitHubE2EIntegrationTests` | **live** vs real API (2) | §38: `octocat/Hello-World` 全链路 (导入→校验 README→同步零下载); §37: XiaoZhangGui `feature/v3.6.1-reference-home` 斜杠分支匹配 (HEAD `6605330`) + 真实导入 (>10 文件, 含 .swift) |
| `WorkspaceSyncTests` | unit (8) | `threeWayDiff` 7 用例 + `apply()` 真实目录验证 (冲突文件保留本地、metadata/manifest 推进) |

E2E 配额保护: 匿名 60 req/h; 剩余 < 20 时 `XCTSkip` (避免 CI 耗尽配额); 可用 `GITHUB_TEST_TOKEN` 环境变量提配额。

UI 点按步骤 (import sheet 填写/点击、同步按钮) 由以上单元+集成测试覆盖逻辑层; 真机点按待用户用 M1 IPA 验收 (Linux 无真机, 诚实标注)。

## 3. Verification

- CI run: [36818096589](https://github.com/kevin2xiaomao-max/CodeBerry/actions/runs/36818096589) — M0 re-run **SUCCESS** (simulator build / PreviewEngineTests / generic device build / IPA package / artifact upload 全绿)
- M1 CI: _pending_ (pushed after this commit)
- 新增测试数: 14 + 10 + 10 + 2 + 8 = 44 个
- 2.0/3.0 回归: `PreviewEngineTests` 必须继续通过 (CI 验证)

## 4. Known limitations / M4 衔接

- 冲突目前只计数+保留本地, 不展示逐文件 diff — M4 做 Conflict UI (Base/Local/Remote)。
- 同步是整包下载 (zipball), 无增量 — 500 文件仓库在 M5 做后台/取消优化 (§26)。
- 私有仓库需要 PAT; 未设置时导入私有库返回 404→unauthorized 映射提示。
- `commit` pin 的导入不同步 (无更新可拉取), 显示"已是最新"。
