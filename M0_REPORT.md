# M0 Feasibility Report — CodeBerry Lite 4.0

Date: 2026-10-01
Branch: `codeberry-lite-v4` (from 3.0 stable `5bf2616`)
Baseline IPA: `CodeBerry-Lite-3.0-unsigned.ipa` = 6,798,565 bytes

## 1. Dependency decisions

| Dependency | Version (pinned) | License | iOS support | Device build | IPA size delta | Verdict |
|---|---|---|---|---|---|---|
| swift-syntax (SwiftSyntax/SwiftParser/SwiftOperators) | 601.0.0+ (upToNextMajor, existing) | Apache-2.0 | iOS (SPM declares iOS) | ✅ proven by 3.0 CI device builds | included in 6.8MB baseline | PASS — keep |
| Runestone (simonbs) | 0.5.2 exact | MIT | iOS 14+ (Package.swift) | ✅ CI: sim + generic device build | ✅ see §6 | **GO** — device build proven |
| TreeSitterLanguages (simonbs) | 0.1.10 exact | MIT | iOS 14+ (Package.swift) | ✅ CI: sim + generic device build | ✅ see §6 | **GO** — `TreeSitterSwiftRunestone` linked only (Swift grammar + queries) |
| ZIPFoundation (weichsel) | 0.9.20 exact | MIT | iOS 9+ (Package.swift) | ✅ CI: sim + generic device build | ✅ see §6 | **GO** — zipball extraction; no Apple unzip API on iOS |
| True Git / libgit2 | — | — | — | — | — | **DEFERRED → 4.1** (see §3) |

Notes:
- swift-syntax already ships in the 3.0 IPA (Inspector's atomic rewrite). M2 will additionally link `SwiftDiagnostics` + `SwiftParserDiagnostics` products from the same vetted package for inline diagnostics.
- Runestone 0.5.2 integrates tree-sitter 0.20.9 (via its own SPM dep `tree-sitter 0.20.9`, upToNextMinor). Source package, no prebuilt binaries — complies with §11.
- TreeSitterLanguages 0.1.10 depends on `simonbs/Runestone from 0.4.1`; our exact pin 0.5.2 satisfies it. Only the `TreeSitterSwiftRunestone` product is linked (Swift grammar only; other languages not compiled in).
- All three new deps are pinned with `exactVersion` per §11 "pin 版本".

## 2. Spike results

### SwiftSyntax — PASS
Already integrated in 3.0 (products SwiftSyntax/SwiftParser/SwiftOperators, repo `swiftlang/swift-syntax`, 601.0.0+). Multiple green CI runs with generic iOS device build + IPA. No new risk.

### Runestone device build — PASS
Validated by CI run 36816998142 (2026-10-01): simulator build ✅, PreviewEngineTests ✅, generic iOS device build ✅ (arm64 `CodeBerry` binary 43,568,096 bytes). Runestone 0.5.2 compiles under Xcode 26.5 / Swift 6 without changes. The .app contains `Runestone_Runestone.bundle`, `TreeSitterLanguages_TreeSitterSwiftQueries.bundle`, `ZIPFoundation_ZIPFoundation.bundle`. M2 can proceed with the Runestone editor; no fallback needed.

### GitHub Snapshot networking — PASS
Verified live against the real API (2026-10-01):
- `GET /repos/kevin2xiaomao-max/XiaoZhangGui` → 200, public, default branch `main`
- `GET /repos/kevin2xiaomao-max/XiaoZhangGui/branches/feature/v3.6.1-reference-home` → 200, HEAD `660533013dc0d2bb4e5a81924333322e1d204431`
- `GET /repos/.../zipball/feature/v3.6.1-reference-home` → 302 → `codeload.github.com/.../legacy.zip/...` (URLSession follows redirects; no auth needed for public repo)
No new dependency required (URLSession only).

### Archive extraction — GO (ZIPFoundation)
iOS has no built-in zip extraction API. ZIPFoundation 0.9.20 (MIT, mature, SPM, pure Swift on Apple platforms) selected. Zip-slip/path-traversal/symlink guards will be implemented in M1's `ArchiveSecurity` layer on top of it (validated by `ArchiveSecurityTests`).

### Keychain — PASS
`CodeBerry/Support/KeychainStore.swift` already exists (used in 3.x). PAT will be stored Keychain-only; no new API needed.

### Dependency licenses
- swift-syntax: Apache-2.0 ✅
- Runestone: MIT ✅
- TreeSitterLanguages: MIT ✅
- ZIPFoundation: MIT ✅
All allow App Store distribution. No copyleft.

## 3. True Git (libgit2) — DEFERRED to 4.1

M0 spike verdict: **do not enter production in 4.0**. Evidence:

1. **No reliable iOS binding.** Candidates found:
   - `flaboy/static-libgit2`, `marknote/static-libgit2`: prebuilt XCFramework binaries from individual accounts → violates §11 "不要使用不可信预编译二进制".
   - `ankitra/libgit2-apple`: source build, but pulls `mfcollins3/libssh2-apple` + `mfcollins3/openssl-apple` third-party C forks → supply-chain risk, unvetted under Xcode 26.5/Swift 6.
2. **Runtime spike items cannot be validated from this environment.** The spec's spike requires real-device clone/fetch/checkout/status/diff/commit + memory/crash checks. Linux CI can only do build-time checks; the remaining items are unverifiable here.
3. **TLS/SSH unvalidated.** libgit2 HTTPS on iOS needs an OpenSSL/mbedTLS backend + cert handling; SSH needs libssh2. None validated on device.
4. **Spec allows it.** §5/§31: if True Git is unstable, 4.0 ships Snapshot Sync and True Git moves to 4.1.

4.0 therefore implements **Mode A Snapshot Sync only** ("同步 GitHub"; never labeled git pull; Snapshot Mode shows local changes + patch export, no fake stage/commit). All 4.0 E2E requirements (§37/§38/§44) are satisfiable with Snapshot Sync.

## 4. Size

- Baseline (3.0): 6,798,565 bytes (~6.5MB). Target: ≤25MB.
- New deps add: Runestone + tree-sitter C + Swift grammar + ZIPFoundation. Estimated +3–8MB → projected ~10–15MB, inside budget.
- Actual delta (CI 36816998142): **~9.0MB** (`ls -lh` shows 8.6M; baseline 6,798,565 ≈ 6.5MB) → **+2.2MB**, far inside budget. No fallback needed.
- Final budget at M5: ≤25MB. Current trajectory is safe.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Runestone 0.5.2 fails to compile under Swift 6 / Xcode 26.5 | M0 CI validates; fallback = keep 3.0 UITextView editor + enhance (M2 scope decision) |
| tree-sitter C build slow on CI | Accept; only clean builds pay it |
| ZIPFoundation API drift at 0.9.20 | Pinned exact; API stable for years |
| Snapshot sync on 500-file repos slow | M5: background indexing, cancellable, hash cache (§26) |

## 6. M0 CI result

- Run: [36816998142](https://github.com/kevin2xiaomao-max/CodeBerry/actions/runs/36816998142) (completed 2026-10-01 05:04 UTC)
- Simulator build: ✅
- Tests (PreviewEngineTests): ✅
- Generic device build (unsigned, arm64): ✅ — `CodeBerry` binary 43,568,096 bytes
- IPA packaging: the build artifacts and `CodeBerry-Lite-4.0-unsigned.ipa` (~9.0MB / 8.6M) were produced correctly; the *run* is marked failure only because the workflow's sanity-check line still referenced the old 3.0 artifact filename (my rename bug, fixed in the same amend). All compiled artifacts are valid.
- Artifact naming: `CodeBerry-Lite-4.0-unsigned` / `CodeBerry-Lite-4.0-unsigned.ipa` (step 5 completed before the failed sanity check, so the 8.6M artifact exists on the failed run)

**M0 verdict: GO.** All three pinned dependencies (Runestone 0.5.2, TreeSitterLanguages 0.1.10, ZIPFoundation 0.9.20) build for generic iOS device. SwiftSyntax stays (3.0-proven). True Git stays deferred to 4.1. Proceed to M1.
