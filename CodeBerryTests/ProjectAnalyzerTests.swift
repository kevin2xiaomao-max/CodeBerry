import XCTest
@testable import CodeBerry

/// §三十九: ProjectAnalyzer — GitHub 导入后的可预览页面分析.
final class ProjectAnalyzerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyzerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func write(_ rel: String, _ text: String) {
        let url = root.appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try! text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testDetectsPreviewMacroAndRanksFirst() {
        write("App.swift", "import SwiftUI\n@main struct App: App { var body: some Scene { WindowGroup { HomeView() } } }\n")
        write("Home/HomeView.swift", """
            import SwiftUI
            struct HomeView: View {
                var body: some View { Text("hi") }
            }
            #Preview { HomeView() }
            """)
        write("Features/Detail/DetailView.swift", """
            import SwiftUI
            struct DetailView: View { var body: some View { Text("d") } }
            """)
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertEqual(a.candidates.count, 2)
        // §8 排序: 有 #Preview 的排第一.
        XCTAssertEqual(a.candidates[0].viewName, "HomeView")
        XCTAssertEqual(a.candidates[0].kind, .macroPreview)
        XCTAssertEqual(a.candidates[1].kind, .featureView)
    }

    func testPageLevelOutranksFeature() {
        write("HomePage.swift", "import SwiftUI\nstruct HomePage: View { var body: some View { Text(\"x\") } }\n")
        write("Features/FooView.swift", "import SwiftUI\nstruct FooView: View { var body: some View { Text(\"x\") } }\n")
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertEqual(a.candidates.map(\.viewName), ["HomePage", "FooView"])
        XCTAssertEqual(a.candidates[0].kind, .pageView)
    }

    func testPreviewProviderDetected() {
        write("P.swift", """
            import SwiftUI
            struct P_Previews: PreviewProvider {
                static var previews: some View { Text("p") }
            }
            """)
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertEqual(a.candidates.first?.kind, .previewProvider)
    }

    func testDesignTokensCollected() {
        write("DS.swift", """
            import SwiftUI
            enum V32Layout {
                static let sectionGap: CGFloat = 16
                static let cardRadius: CGFloat = 12
            }
            """)
        let a = ProjectAnalyzer.analyze(root: root)
        let refs = Set(a.tokens.map(\.reference))
        XCTAssertTrue(refs.contains("V32Layout.sectionGap"))
        XCTAssertTrue(refs.contains("V32Layout.cardRadius"))
    }

    func testViewModifiersAndShapesCollected() {
        write("M.swift", """
            import SwiftUI
            struct CardStyle: ViewModifier {
                func body(content: Content) -> some View { content }
            }
            struct Badge: Shape {
                func path(in rect: CGRect) -> Path { Path() }
            }
            """)
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertTrue(a.viewModifiers.contains("CardStyle"))
        XCTAssertTrue(a.shapes.contains("Badge"))
    }

    func testSearchFilters() {
        write("A.swift", "import SwiftUI\nstruct AlphaView: View { var body: some View { Text(\"a\") } }\n")
        write("B.swift", "import SwiftUI\nstruct BetaView: View { var body: some View { Text(\"b\") } }\n")
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertEqual(a.search("alpha").map(\.viewName), ["AlphaView"])
        XCTAssertEqual(a.search("").count, 2)
    }

    func testSyntaxErrorFlaggedNotDropped() {
        write("Broken.swift", "import SwiftUI\nstruct BrokenView: View { var body: some View { Text(\"x\" ")
        let a = ProjectAnalyzer.analyze(root: root)
        // 坏文件不污染其他文件: candidate 仍在, 但标记语法错误.
        XCTAssertTrue(a.candidates.contains { $0.viewName == "BrokenView" && $0.hasSyntaxError })
    }

    func testProjectKindDetection() {
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("Foo.xcodeproj"),
                                                 withIntermediateDirectories: true)
        let a = ProjectAnalyzer.analyze(root: root)
        XCTAssertEqual(a.projectKind, .xcodeproj)
    }

    func testCancellationStopsScan() {
        write("A.swift", "import SwiftUI\nstruct A: View { var body: some View { Text(\"a\") } }\n")
        let a = ProjectAnalyzer.analyze(root: root, isCancelled: { true })
        XCTAssertEqual(a.fileCount, 0)
    }
}
