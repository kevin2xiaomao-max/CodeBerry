# ADR-001: Native Preview Service (reserved interface)

- Status: **Accepted (interface only)** — 4.0.3 reserves the interface; no implementation.
- Date: 2026-10-02
- Deciders: CodeBerry 4.0.3 plan review (user-approved 2026-10-02)

## Context

CodeBerry's preview engine is an *approximation* pipeline: it parses SwiftUI
source, resolves symbols through `PreviewResolver`, and renders an estimated
view tree with diagnostics (`PreviewEvaluator`). For the V3.6 real-project
corpus (4.0.3), the 6 red-line identifiers (`DemoMode`, `greetingPrefix`,
`V32`, `ownerDisplayName`, `handlingItems`, `Calendar`) are now resolved or
gracefully degraded — but approximation has a ceiling:

- Real layout (HStack spacing, GeometryReader, scroll offsets) is guessed.
- Custom `ViewModifier`s and complex generics degrade to placeholders.
- The user can never be *sure* the canvas matches Xcode's `#Preview`.

The long-term answer is a **native render**: compile the real view on a Mac
(via axe / swiftui-render research, or a small Mac helper service) and return
an image + accessibility hierarchy.

## Decision

1. 4.0.3 adds `NativePreviewService` as a **protocol-only** reservation
   (`CodeBerry/Preview/NativePreviewService.swift`): `render(_:)`,
   `isAvailable`, request/result value types. No implementation, no network
   code, no axe/swiftui-render integration.
2. The approximation pipeline remains the **only** engine in 4.0.3. When a
   future service implements the protocol, call sites adopt it as a
   progressive enhancement: native render where available, approximation
   fallback otherwise.
3. Research spike (axe, swiftui-render) is documented here, not executed.

## Consequences

- Call sites written against the protocol in 4.1+ won't need rewrites.
- 4.0.3 ships zero new dependencies and zero new permissions/entitlements.
- Risk if never implemented: the protocol is ~50 lines of dead interface —
  acceptable; it documents intent and keeps the seam visible.

## Alternatives considered

- **Implement now**: rejected — 4.0.3 scope is the approximation pipeline's
  correctness on the V3.6 corpus; a Mac service is a separate project with
  its own auth/sandboxing questions.
- **No interface**: rejected — without the seam, a future native renderer
  would require refactoring every call site.
