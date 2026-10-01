import XCTest
@testable import CodeBerry

/// §三十九: PreviewReadiness — 页面无法预览时给出精确状态 + 动作.
final class PreviewReadinessTests: XCTestCase {
    func testReadyPage() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View { Text("hi") }
            }
            """)
        XCTAssertTrue(r.isReady)
        if case .ready = r.primary {} else { XCTFail("expected ready") }
    }

    func testSwiftDataIsUnsupportedRuntime() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            import SwiftData
            struct HomeView: View {
                @Query var items: [Item]
                var body: some View { Text("hi") }
            }
            """)
        if case .unsupportedRuntime(let deps) = r.primary {
            XCTAssertTrue(deps.contains("SwiftData"))
        } else { XCTFail("expected unsupportedRuntime, got \(r.primary)") }
        XCTAssertTrue(r.actions.contains(.createMock))
        XCTAssertTrue(r.actions.contains(.generateFixture))
    }

    func testRepositoryNeedsMock() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                let repository: HomeRepository
                var body: some View { Text("hi") }
            }
            """)
        if case .needsMock(let reasons) = r.primary {
            XCTAssertTrue(reasons.contains { $0.contains("HomeRepository") })
        } else { XCTFail("expected needsMock, got \(r.primary)") }
        XCTAssertTrue(r.actions.contains(.createMock))
    }

    func testChartsIsExternalPackage() {
        let r = PreviewReadiness.report(of: "ChartView", in: """
            import SwiftUI
            import Charts
            struct ChartView: View {
                var body: some View { Text("c") }
            }
            """)
        if case .externalPackageNotExecuted(let pkgs) = r.primary {
            XCTAssertTrue(pkgs.contains("Charts"))
        } else { XCTFail("expected externalPackageNotExecuted, got \(r.primary)") }
        XCTAssertTrue(r.actions.contains(.ignoreNonVisual))
    }

    func testUnknownCustomViewIsMissingComponent() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View { FancyCarousel(items: []) }
            }
            """)
        if case .missingComponentSupport(let comps) = r.primary {
            XCTAssertTrue(comps.contains("FancyCarousel"))
        } else { XCTFail("expected missingComponentSupport, got \(r.primary)") }
    }

    func testKnownViewIsNotMissingComponent() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View { VStack { Text("a") } }
            }
            """,
            knownViews: ["HomeView"])
        XCTAssertTrue(r.isReady)
    }

    func testSyntaxErrorIsRed() {
        let r = PreviewReadiness.report(of: "Bad", in: "struct Bad: View { var body: some View { Text(\"x\" ")
        if case .syntaxError = r.primary {} else { XCTFail("expected syntaxError") }
        XCTAssertEqual(r.actions, [.viewDiagnostics])
    }

    func testSecondaryIssuesAreKept() {
        // SwiftData (red) + Repository (yellow): 主状态是 red, yellow 进 secondary.
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            import SwiftData
            struct HomeView: View {
                let repository: HomeRepository
                var body: some View { Text("hi") }
            }
            """)
        if case .unsupportedRuntime = r.primary {} else { XCTFail("primary should be red") }
        XCTAssertTrue(r.secondary.contains { if case .needsMock = $0 { return true }; return false })
    }
}
