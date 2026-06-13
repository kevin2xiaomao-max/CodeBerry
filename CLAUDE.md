# CodeBerry — Project Context

## What this is

The iOS app from the AgentOS long-term vision (see `../AgentOS/CLAUDE.md`): an
Xcode-like Swift editor for iPhone/iPad where users create/read/edit/delete
Swift files and chat with an AI coding agent that writes code into the same
workspace. The agent framework is **AgentKit**, linked as a local Swift package
from `../AgentOS/AgentKit` — never duplicate agent/model/tool logic here.

## Environment & key decisions

- Target: **iOS 26**, Swift 6 (strict concurrency), Xcode 26.5, `objectVersion = 77`
  pbxproj with a file-system-synchronized root group (new files under
  `CodeBerry/` are picked up automatically — never edit the pbxproj to add files).
- Default model: **On-Device (Apple Intelligence)** via FoundationModels; Claude
  (Anthropic API, key `anthropic-api-key`) and GPT (OpenAI, `openai-api-key`)
  keys live in the Keychain only. API key ≠ Claude.ai subscription in UI copy.
- Workspace root = the app's **Documents folder** (visible in the Files app via
  `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`). Editor and
  agent file tools operate on the same `AgentKit.Workspace`.
- Editor uses **TextKit 1** (explicit NSTextStorage/NSLayoutManager stack) so
  layoutManager-based line-number geometry works; don't migrate to TextKit 2
  without reworking `LineNumberGutter`.
- **Preview canvas is an interpreter, not a compiler** (iOS apps can't compile
  or run code — Apple-only entitlements). `swift-syntax` (601.x, remote SPM
  dep) parses the open file; a tree-walking evaluator maps a curated SwiftUI
  subset onto real views. Anything outside the subset degrades to a warning
  chip — extend the subset in `PreviewEvaluator+Calls.swift`, never crash.
  The owner-approved roadmap for full fidelity is a companion-Mac build/stream
  ("Option B"), not on-device compilation.

## Architecture map

```
CodeBerry/
├── CodeBerryApp.swift        Creates WorkspaceStore + ChatViewModel (shared root)
├── ContentView.swift         Home (ProjectsListView) ⇄ NavigationSplitView (navigator |
│                             editor) switched on store.currentProject; chat via .inspector
├── Workspace/
│   ├── WorkspaceStore.swift  @Observable: projects (top-level folders), currentProject,
│   │                         file tree (scoped to project), tabs, editor buffer, autosave
│   │                         (1s), create/delete/rename, createProject (scaffolds via
│   │                         AgentKit CreateXcodeProjectTool), agent-mutation reload
│   ├── ProjectsListView.swift   Home screen: project rows (app/folder tiles), "+" new
│   │                            project alert, Settings menu, rename/delete
│   └── FileNavigatorView.swift  Per-project tree, "‹ Projects" back, context menus,
│                                new file/folder alerts
├── Editor/
│   ├── SwiftHighlighter.swift   Regex highlighting, Xcode Default light/dark theme colors
│   ├── CodeTextView.swift       UITextView subclass: TextKit 1, floating line-number gutter
│   ├── CodeEditorView.swift     UIViewRepresentable; auto-indent, bracket pairing,
│   │                            EditorController (completion insert, keyboard dismiss)
│   ├── AutocompleteEngine.swift Keywords + common symbols + document identifiers
│   └── EditorPaneView.swift     Open-file tabs, editor, keyboard accessory bar
├── Preview/
│   ├── PreviewEngine.swift      swift-syntax parsing → PreviewDocument (View structs,
│   │                            @State props, body, #Preview block); operators pre-folded
│   ├── PreviewEvaluator.swift   PreviewValue, PreviewRuntime (@Observable state store,
│   │                            version bump = re-render), expression/if/action evaluation
│   ├── PreviewEvaluator+Calls.swift  View factories (Text/stacks/Button/ForEach/custom
│   │                            structs…), modifier table, contextual arg helpers
│   ├── PreviewRender.swift      PreviewViewNode model + PreviewNodeView (maps nodes
│   │                            onto real SwiftUI), modifier application
│   └── PreviewCanvasView.swift  Canvas UI: debounce, light/dark, state restart, warnings
├── Chat/
│   ├── ChatViewModel.swift   Port of AgentOS macOS VM + onWorkspaceMutated/onBeforeSend hooks
│   ├── ChatView.swift        Headerless; Liquid Glass composer (glassEffect) holds the
│   │                         "+" menu (new chat), model selector menu, and send button
│   └── SettingsView.swift    Keychain API keys, workspace info — presented from the
│                             navigator's ellipsis menu (ContentView sheet), not the chat
└── Support/
    ├── KeychainStore.swift
    └── CompanionStore.swift  Discovers/connects to a Mac running AgentOS
                              (AgentKit Companion* APIs); surfaced in Settings.
                              Bonjour keys live in CodeBerryInfo.plist (merged
                              with the generated Info.plist via INFOPLIST_FILE).
```

## Conventions

- @Observable (not ObservableObject), @MainActor on stores/VMs, Swift 6 strict.
- Agent capabilities (tools, models, knowledge) belong in AgentKit, not here.
- Secrets only in Keychain; never in source or UserDefaults.
- Build check: `xcodebuild -project CodeBerry.xcodeproj -scheme CodeBerry
  -destination 'generic/platform=iOS Simulator' build` (shared scheme committed).

## State (June 2026)

Builds and launches on the iOS 26.5 simulator (iPhone 17 Pro). First launch
bootstraps `Welcome.swift`; the last-opened file is restored on relaunch
(UserDefaults `lastOpenFilePath`). Verified: highlighting, gutter, accessory
bar, navigator CRUD, chat wiring, preview canvas rendering WelcomeView with
zero warnings (live re-parse on edit, interpreted @State + button actions).
Companion-Mac handshake (Option B step 1) verified end-to-end: Bonjour
discovery + hello/welcome/ping from the simulator to a Mac server
(`swift run companion-demo serve` in ../AgentOS/AgentKit, or the AgentOS Mac
app itself), plus manual host:port connect. OWNER REQUIREMENT: the link must
work without shared WiFi — transports use includePeerToPeer (AWDL, nearby
devices) and the manual-address path covers remote (Tailscale/VPN); AWDL
needs real-device testing (no simulator support). Next: build/run commands
over that link; eventually a relay for any-distance zero-config.
Not yet exercised end-to-end: Claude/GPT backends on device, agent → editor
live-reload during a real session, preview interactions (taps/toggles) on
device.
