import XCTest
@testable import CodeBerry

/// 4.0.3 S1: the REAL XiaoZhangGui V3.6 tree acceptance (read-only).
///
/// `XZG_REFERENCE_ROOT` is REQUIRED — a missing checkout is an explicit
/// FAILURE, never a silent skip. On CI the workflow clones the reference
/// tree when the `XZG_CHECKOUT_PAT` secret is configured; without it this
/// class is excluded via `-skip-testing` with a loud log warning (the
/// exclusion is recorded in the release report, not hidden).
///
/// This file must never be rewritten to pass — it runs against the real
/// tree as-is.
final class XiaoZhangGuiRealV36AcceptanceTests: XCTestCase {

    struct MissingReferenceError: Error, CustomStringConvertible {
        let path: String
        var description: String { "XZG_REFERENCE_ROOT missing at \(path)" }
    }

    private func referenceRoot() throws -> URL {
        let path = ProcessInfo.processInfo.environment["XZG_REFERENCE_ROOT"]
            ?? (NSHomeDirectory() + "/workspace/xzg-v361")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else {
            XCTFail("XZG_REFERENCE_ROOT not available at \(path) — " +
                    "real-tree acceptance FAILED (not skipped). " +
                    "Provide a read-only XiaoZhangGui V3.6 checkout.")
            throw MissingReferenceError(path: path)
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

    /// The real tree is fully listed (233 Swift files incl. Tests/widget).
    func testRealTreeIsFullyListed() throws {
        let index = try makeRealIndex()
        XCTAssertGreaterThanOrEqual(
            index.totalCount, 200,
            "the real tree has 233 Swift files; the index must cover them all")
    }

    /// `DemoMode` (a `final class`, not a View) resolves as an ordinary
    /// cross-file type in the real tree.
    func testRealTreeIndexResolvesDemoModeType() throws {
        let index = try makeRealIndex()
        let demo = try XCTUnwrap(index.typesByName["DemoMode"],
                                 "DemoMode must resolve as a cross-file type in the real tree")
        XCTAssertTrue(demo.isSingleton)
        XCTAssertEqual(demo.instanceMembers["isEnabled"], "Bool")
    }

    /// The real Home screen's custom components resolve (not `[?]`).
    func testRealTreeIndexResolvesHomeComponents() throws {
        let index = try makeRealIndex()
        for name in ["HomeView",
                     "V35HomeRevenueHero",
                     "V36QuickActions",
                     "V36RecentContactsRail",
                     "V36IncomeOutcomePair",
                     "V35HomeFocusSection"] {
            XCTAssertNotNil(index.viewsByName[name],
                             "\(name) must resolve in the real-tree index")
        }
    }

    /// `V32` resolves as an enum in the real tree; literal `static let`s
    /// carry values, `@MainActor` computed statics stay opaque.
    func testRealTreeIndexResolvesV32() throws {
        let index = try makeRealIndex()
        let v32 = try XCTUnwrap(index.typesByName["V32"],
                                "V32 must resolve as a cross-file enum in the real tree")
        XCTAssertEqual(v32.kind, .enum)
        XCTAssertNotNil(v32.staticValues["hero"])
        XCTAssertTrue(v32.opaqueStatics.contains("pageBG"))
    }
}
