# PreviewFixtures

Smoke-test fixtures for the CodeBerry Lite **Preview interpreter**
(`CodeBerry/Preview/`), introduced in Lite 2.0.

These files are **not** part of the app target:

- they are NOT referenced by `CodeBerry.xcodeproj`
- they are NOT compiled by `xcodebuild` / GitHub Actions
- they do not affect the shipped app in any way

## How to use

1. Open the in-app Editor.
2. Paste the contents of `V36CodeBerryPreview.swift` into it.
3. Watch the Preview canvas.

## What `V36CodeBerryPreview.swift` covers

A realistic page structure (not a flattened sample):

- 7 computed subviews: `header`, `revenueHero`, `quickActions`,
  `contactsRail`, `metricPair`, `weekRail`, `floatingTabBar`
- 6 helper functions: `circleButton(_:)`, `pill(_:_:)`, `contact(_:_:)`,
  `metric(_:_:_:)`, `day(_:_:_:)`, `tab(_:_:_:)` — covering unlabeled params,
  multiple params, `String` / `Bool` / `Int`
- `@State selectedTab` + `Button { selectedTab = index } label: { … }`
  + `if selectedTab == index` conditional rendering
- Color constants, `VStack` / `HStack` / `ZStack`, `ScrollView`, `Spacer`,
  `Text`, `Image(systemName:)`, `Button`, shapes
- `.background(_:in:)` with `RoundedRectangle` / `Capsule` / `Circle`
- `.overlay` + `.stroke`
- `.ultraThinMaterial` background
- ternary colors, `if` in builders, `@State` assignment in actions

## Acceptance gate

`XiaoZhangGui_CodeBerry_V36Preview.swift` is the **final regression gate**:
a byte-for-byte copy of the original file that failed on 1.0 with seven
`Unknown identifier` warnings. **Do not simplify or rewrite it** — it must
run as-is, with zero `Unknown identifier` warnings.

`V36CodeBerryPreview.swift` is a second, hand-built fixture covering the
same engine surface (kept for readability); it is not the gate.
