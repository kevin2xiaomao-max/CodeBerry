import XCTest
@testable import CodeBerry

/// 4.0.2 P0-4: readiness must not report Swift/stdlib/Foundation/SwiftUI
/// non-view call names as "missing custom component support".
///
/// Regression context: the old filter (uppercase first letter only) pushed
/// perfectly previewable pages into 🟡 for `Array`, `Binding`, `Date`,
/// `Locale`, `String`, `StrokeStyle`, `ToolbarItem`, `WindowGroup`,
/// `NSStringFromString`, …
final class PreviewReadinessClassificationTests: XCTestCase {

    private func missingComponents(in report: PreviewReadiness.Report) -> [String] {
        var out: [String] = []
        let collect: (PreviewReadiness.Status) -> Void = { status in
            if case .missingComponentSupport(let comps) = status { out += comps }
        }
        collect(report.primary)
        report.secondary.forEach(collect)
        return out
    }

    func testStdlibAndFoundationCallsAreNotMissingComponents() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View {
                    VStack {
                        Text(String(describing: Date()))
                        Text("\\(Array(repeating: 1, count: 3).count)")
                        Text(Locale.current.identifier)
                        Text(NSStringFromString("x") as String)
                    }
                }
            }
            """)
        XCTAssertTrue(missingComponents(in: r).isEmpty,
                      "stdlib/Foundation calls must not be missing components, got: \(missingComponents(in: r))")
        XCTAssertTrue(r.isReady)
    }

    func testStrokeStyleAndBindingAreNotMissingComponents() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                @State private var v = false
                var body: some View {
                    Circle()
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [4]))
                }
            }
            """)
        XCTAssertTrue(missingComponents(in: r).isEmpty,
                      "got: \(missingComponents(in: r))")
        XCTAssertTrue(r.isReady)
    }

    func testToolbarItemIsKnown() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View {
                    Text("hi")
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("x") {}
                            }
                        }
                }
            }
            """)
        XCTAssertTrue(missingComponents(in: r).isEmpty,
                      "ToolbarItem is a SwiftUI built-in, got: \(missingComponents(in: r))")
        XCTAssertTrue(r.isReady)
    }

    func testWindowGroupIsKnown() {
        let r = PreviewReadiness.report(of: "MyApp", in: """
            import SwiftUI
            @main
            struct MyApp: App {
                var body: some Scene {
                    WindowGroup {
                        Text("hi")
                    }
                }
            }
            """)
        XCTAssertTrue(missingComponents(in: r).isEmpty,
                      "WindowGroup is a SwiftUI built-in, got: \(missingComponents(in: r))")
        XCTAssertTrue(r.isReady)
    }

    func testGenuinelyUnknownCustomViewIsStillFlagged() {
        let r = PreviewReadiness.report(of: "HomeView", in: """
            import SwiftUI
            struct HomeView: View {
                var body: some View { MysteryWidget(data: []) }
            }
            """)
        XCTAssertTrue(missingComponents(in: r).contains("MysteryWidget"),
                      "genuinely unknown custom views must still be flagged")
        XCTAssertFalse(r.isReady)
    }
}
