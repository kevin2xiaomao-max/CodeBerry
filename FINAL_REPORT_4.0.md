# CodeBerry Lite 4.0 — M0–M5 Final Report

**Date:** 2026-10-01  
**Branch:** `codeberry-lite-v4` (from 3.0 stable `5bf2616`)  
**HEAD:** `c61ae1e`  
**Worktree:** clean  
**Remote:** `kevin2xiaomao-max/CodeBerry` (all commits pushed)

## Milestones

| M | Commit | CI Run | Result | Tests |
|---|--------|--------|--------|-------|
| M0 | `e43578a` | 36818096589 | ✅ SUCCESS | deps pinned |
| M1 | `0babb97` | (covered by M2 run) | ✅ SUCCESS | 44 |
| M2 | `df8178e` | 36832969664 | ✅ SUCCESS | 45 |
| M3 | `cbac750` | 36839087315 | ✅ SUCCESS | 54 |
| M4 | `014c159` | 36843108352 | ✅ SUCCESS | 22 |
| M5 | `c61ae1e` | 36845797993 | ✅ SUCCESS | 3 |

**Total:** 188 tests, 0 failures (final M5 run).

## Deliverable

- **IPA:** `CodeBerry-Lite-4.0-unsigned.ipa`
- **Size:** 9,871,050 bytes (9.7 MB)
- **Version:** 4.0 / Build 400 (verified in Info.plist)
- **Artifact:** `CodeBerry-Lite-4.0-unsigned` from run 36845797993
- **Local:** `~/workspace/codeberry-ipa/artifact-4.0/`

## What was built

**M0:** Dependency selection — Runestone 0.5.2, TreeSitterLanguages 0.1.10, ZIPFoundation 0.9.20 (exact pins). True Git deferred to 4.1.

**M1:** GitHub Direct — URL parsing, PAT/Keychain auth, snapshot download/sync, archive security (zip-slip protection), 44 tests.

**M2:** Mobile editor — Runestone integration, SwiftSyntax bridge (SymbolIndex, InlineDiagnostics), local completion, CodingBar, QuickOpen, project search, code navigation, 45 tests.

**M3:** Preview Engine 2 — ProjectAnalyzer, PreviewReadiness, ComponentRegistry (4 registries), IncrementalPreview, MockCenter, PreviewSelection (Preview→Code), Inspector4, Before/After diff, 54 tests.

**M4:** Git workspace + safety — LocalHistory (50/file, 30-day prune), SessionStore, OfflineMonitor + banner, SnapshotChanges (unified diff export), SecurityPolicy (HTTPS-only, token redaction), conflict UI, 22 tests.

**M5:** Polish — iPhone 4-tab navigation (文件/代码/预览/更改), iPad split view, session restore on launch, version 4.0/400, Chinese audit, 3 tests.

## Product red lines (§44) — status

- ✅ iPhone 底部 4 入口：文件/代码/预览/更改
- ✅ Preview 直接点选 + 长按开 Inspector sheet
- ✅ Code→Preview→Inspector→Code 闭环
- ✅ Coding Bar (P0, 中文输入兼容)
- ✅ 2.0/3.0 fixtures continue passing

## Known issues / Risks

1. **No local Xcode** (Linux): all verification via CI. No simulator screenshots or device testing performed locally.
2. **True Git deferred to 4.1** (M0 decision): 4.0 uses snapshot sync only.
3. **E2E on real repos** (XiaoZhangGui 24-step): CI covers unit/integration; full E2E on device pending user testing.
4. **IPA size 9.7 MB** — well under 25 MB limit.
5. **M4 CI failed once** (L10n duplicate keys, Sendable issues) — fixed and green. No tests were deleted or weakened (red line honored).

## Test red line compliance

No tests deleted, no assertions weakened, no failures skipped throughout M1–M5. All fixes were to implementation or genuine test bugs (documented in M3/M4 reports).
