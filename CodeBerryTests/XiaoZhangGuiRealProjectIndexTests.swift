import XCTest
@testable import CodeBerry

/// 4.0.2 E2E (§12 items 5/7/11): the project index built over the REAL
/// XiaoZhangGui checkout (read-only) resolves the Home screen's custom
/// components and DemoMode — the exact things that rendered as `[?]` or
/// raised unknown-identifier errors on device.
///
/// The reference path can be overridden with `XZG_REFERENCE_ROOT`; when
/// the checkout is absent (e.g. CI) the test skips loudly instead of
/// failing. This file must never be rewritten to pass — it runs against
/// the real tree as-is.
final class XiaoZhangGuiRealProjectIndexTests: XCTestCase {

    private func referenceRoot() throws -> URL {
        let path = ProcessInfo.processInfo.environment["XZG_REFERENCE_ROOT"]
            ?? (NSHomeDirectory() + "/workspace/xzg-v361")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else {
            throw XCTSkip("XiaoZhangGui reference checkout not available at \(path)")
        }
        return URL(fileURLWithPath: path)
    }

    private func makeRealIndex() throws -> PreviewProjectIndex {
        let root = try referenceRoot()
        let homeRel = "XiaoZhangGui/Features/Home/HomeView.swift"
        let index = PreviewProjectIndex()
        index.update(
            projectRoot: root,
            projectName: "XiaoZhangGui",
            currentPath: homeRel,
            currentSource: try String(
                contentsOf: root.appendingPathComponent(homeRel), encoding: .utf8),
            readFile: { path in
                let prefix = "XiaoZhangGui/"
                let rel = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
                return try? String(
                    contentsOf: root.appendingPathComponent("XiaoZhangGui")
                        .appendingPathComponent(rel),
                    encoding: .utf8)
            })
        return index
    }

    /// §12.5 + §12.11: project custom views are found; the five Home
    /// components must resolve (not `[?]`).
    func testRealTreeIndexResolvesHomeComponents() throws {
        let index = try makeRealIndex()

        XCTAssertGreaterThanOrEqual(
            index.totalCount, 200,
            "the real tree has 233 Swift files; the index must cover them all")
        XCTAssertEqual(index.indexedCount, index.totalCount)
        for name in ["HomeView",
                     "V35HomeRevenueHero",
                     "V36QuickActions",
                     "V36RecentContactsRail",
                     "V36IncomeOutcomePair",
                     "V35HomeFocusSection"] {
            XCTAssertNotNil(index.viewsByName[name],
                             "\(name) must resolve in the real-tree index (E2E §12.11)")
        }
    }

    /// §12.7: `DemoMode` (a `final class`, not a View) resolves as an
    /// ordinary cross-file type instead of an unknown identifier.
    func testRealTreeIndexResolvesDemoModeType() throws {
        let index = try makeRealIndex()

        XCTAssertNotNil(index.typesByName["DemoMode"],
                         "DemoMode must resolve as a cross-file type (E2E §12.7)")
    }
}
