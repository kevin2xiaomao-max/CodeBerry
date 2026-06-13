# CodeBerry

An Xcode-like Swift code editor for iPhone and iPad — with an AI coding agent built right in.

Write, read, and edit Swift files in a project workspace. Open the agent chat and ask it to build something: it creates files, writes code, and the editor live-reloads around it. A live preview canvas renders your SwiftUI views as you type.

---

## Features

- **Full-featured Swift editor** — syntax highlighting (Xcode Default theme), line numbers, auto-indent, bracket pairing, and a keyboard accessory bar
- **File navigator** — create, rename, delete files and folders; multiple open tabs
- **SwiftUI preview canvas** — debounced live re-parse via `swift-syntax`; interprets a SwiftUI subset into real views, including `@State` and button interactions
- **AI coding agent** — chat panel powered by [AgentKit](https://github.com/osantos-io/AgentOS); supports On-Device (Apple Intelligence), Claude (Anthropic), and GPT (OpenAI)
- **Project workspace** — top-level project folders, visible in the Files app; agents and editor share the same workspace
- **Mac companion** — Bonjour + manual host:port connection to a paired Mac running AgentOS; works over AWDL (nearby devices) and manual/VPN paths without shared Wi-Fi

---

## Requirements

| | |
|---|---|
| iOS | 26+ |
| Xcode | 26.5+ |
| Swift | 6 (strict concurrency) |
| Device | iPhone or iPad; Mac companion requires a real device for AWDL |

---

## Getting Started

1. **Clone the repo**
   ```bash
   git clone https://github.com/osantos-io/CodeBerry.git
   cd CodeBerry
   ```

2. **Open in Xcode**
   ```bash
   open CodeBerry.xcodeproj
   ```
   AgentKit is linked as a local Swift package from a sibling directory (`../AgentOS/AgentKit`). Clone [AgentOS](https://github.com/osantos-io/AgentOS) next to this repo so Xcode can resolve it.

3. **Run** — select the `CodeBerry` scheme, choose an iOS 26 simulator or device, and hit Run.

4. **Add API keys (optional)** — open Settings in the app to enter an Anthropic or OpenAI key. The On-Device model works without any key.

---

## Architecture

```
CodeBerry/
├── CodeBerryApp.swift         App entry point; creates shared WorkspaceStore + ChatViewModel
├── ContentView.swift          Home ↔ project split view; chat inspector
├── Workspace/
│   ├── WorkspaceStore.swift   Projects, file tree, tabs, editor buffer, autosave
│   ├── ProjectsListView.swift Home screen — project tiles, new project, settings
│   └── FileNavigatorView.swift Per-project navigator with context menus
├── Editor/
│   ├── CodeTextView.swift     UITextView subclass — TextKit 1, line-number gutter
│   ├── CodeEditorView.swift   UIViewRepresentable wrapper; auto-indent, bracket pairing
│   ├── SwiftHighlighter.swift Regex-based syntax highlighting (Xcode Default palette)
│   ├── AutocompleteEngine.swift Keywords + document identifiers
│   └── EditorPaneView.swift   Tab bar + editor + keyboard accessory
├── Preview/
│   ├── PreviewEngine.swift    swift-syntax → PreviewDocument
│   ├── PreviewEvaluator.swift Interpreter: @State, expressions, actions
│   ├── PreviewEvaluator+Calls.swift View factories and modifier table
│   ├── PreviewRender.swift    PreviewViewNode → real SwiftUI
│   └── PreviewCanvasView.swift Canvas UI: debounce, light/dark, state restart
├── Chat/
│   ├── ChatViewModel.swift    AgentKit session; project-scoped workspace
│   ├── ChatView.swift         Liquid Glass composer; model selector
│   └── SettingsView.swift     API keys + companion settings
└── Support/
    ├── KeychainStore.swift    API key storage
    └── CompanionStore.swift   Bonjour discovery + manual connect to Mac companion
```

**Key design decisions:**

- **TextKit 1** — explicit `NSTextStorage`/`NSLayoutManager` stack for layout-manager-based line-number geometry; do not migrate to TextKit 2 without reworking `LineNumberGutter`.
- **Preview is an interpreter, not a compiler** — iOS apps cannot compile or run arbitrary code. `swift-syntax` parses the open file and a tree-walking evaluator maps a curated SwiftUI subset onto real views. Out-of-subset constructs degrade gracefully to a warning chip.
- **Agent workspace scoping** — the chat agent's file tools are rooted at the open project folder, so relative paths like `Welcome.swift` resolve correctly without needing the project prefix.

---

## Related

- [AgentOS](https://github.com/osantos-io/AgentOS) — the Mac app and AgentKit framework this project depends on

---

## License

MIT
