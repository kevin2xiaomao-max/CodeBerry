# M5 Report — Polish & Release (CodeBerry Lite 4.0)

## Scope (§44 product red lines)
- iPhone 4-tab navigation: 文件 | 代码 | 预览 | 更改
- iPad: NavigationSplitView (files/code left, preview right)
- Session restore on launch
- Version 4.0 / build 400
- Chinese audit, dark mode verification

## Changes
- `CodeBerry/Workspace/FourTabView.swift` (new): TabView with 4 tabs
  - Files: FileNavigatorView (select → auto-switches to Code)
  - Code: EditorPaneView with preview hidden
  - Preview: PreviewCanvasView standalone (Preview → Code via notification)
  - Changes: ChangesTabView wired to SnapshotChanges
- `CodeBerry/ContentView.swift`: adaptive layout (compact → FourTabView, regular → split)
- `CodeBerry/Editor/EditorPaneView.swift`: `previewInitiallyVisible` parameter
- `CodeBerry/Workspace/WorkspaceStore.swift`: `restoreSession()` on launch
- `CodeBerry/Support/L10n.swift`: 5 new keys (filesTab, codeTab, previewTab, previewNoFile, previewNoFileHint)
- `project.pbxproj`: MARKETING_VERSION 4.0, CURRENT_PROJECT_VERSION 400
- `CodeBerryTests/M5PolishTests.swift` (new): 3 tests (L10n completeness, tab distinctness, session tab persistence)

## Tests
- 3 new tests in M5PolishTests
- Full suite: M0(??) + M1(44) + M2(45) + M3(54) + M4(22) + M5(3)

## Verification
- [ ] CI green
- [ ] 4-tab navigation on iPhone
- [ ] Session restore works
- [ ] Version 4.0/build 400 in IPA
