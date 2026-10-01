import XCTest

/// 4.0.1 P0-1 iPhone UI flow (XCUITest):
/// Launch → Projects → Open Workspace → Code → Preview → Changes →
/// Back to Projects (via the unified workspace title menu) →
/// reopen Workspace → kill App → restore Session → Back to Projects.
///
/// Tab indices: 0 Files · 1 Code · 2 Preview · 3 Changes.
/// Labels are matched bilingually ("Projects"/"项目" etc.) so the test
/// does not depend on the simulator locale.
final class WorkspaceFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    private var tabBar: XCUIElement { app.tabBars.firstMatch }

    private func tapTab(index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let button = tabBar.buttons.element(boundBy: index)
        XCTAssertTrue(button.waitForExistence(timeout: 10),
                      "tab \(index) missing", file: file, line: line)
        button.tap()
        XCTAssertTrue(tabBar.buttons.element(boundBy: index).isSelected,
                      "tab \(index) not selected", file: file, line: line)
    }

    private func assertInWorkspace(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15),
                      "expected the 4-tab workspace", file: file, line: line)
        XCTAssertEqual(tabBar.buttons.count, 4,
                       "workspace must keep exactly 4 tabs", file: file, line: line)
    }

    private func assertInProjects(file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["project-row-Welcome"]
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "expected the Projects list", file: file, line: line)
    }

    /// Opens the unified workspace title menu (P0-1) by tapping the
    /// navigation-bar title, then taps Back to Projects.
    private func backToProjectsViaTitleMenu(titleLabels: [String],
                                            file: StaticString = #filePath,
                                            line: UInt = #line) {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10),
                      "no navigation bar on this tab", file: file, line: line)
        let titlePredicate = NSPredicate(format: "label IN %@", titleLabels)
        let titleButton = navBar.buttons.matching(titlePredicate).firstMatch
        if titleButton.waitForExistence(timeout: 5) {
            titleButton.tap()
        } else {
            // Fallback: the title may be exposed as static text.
            let titleText = navBar.staticTexts.matching(titlePredicate).firstMatch
            XCTAssertTrue(titleText.waitForExistence(timeout: 5),
                          "title menu anchor not found", file: file, line: line)
            titleText.tap()
        }
        // The menu item may surface as a button or a menu item.
        let backPredicate = NSPredicate(format: "label IN %@", ["Projects", "项目"])
        var back: XCUIElement?
        for query in [app.buttons.matching(backPredicate),
                      app.menuItems.matching(backPredicate)] as [XCUIElementQuery] {
            let candidate = query.firstMatch
            if candidate.waitForExistence(timeout: 5) {
                back = candidate
                break
            }
        }
        guard let back else {
            XCTFail("workspace title menu did not open", file: file, line: line)
            return
        }
        back.tap()
    }

    // MARK: - Flow

    func testWorkspaceFullFlow() throws {
        // Launch → Projects. Self-stabilizing: a previous run may have left
        // the app inside a restored workspace.
        if tabBar.waitForExistence(timeout: 5) {
            tapTab(index: 3)
            backToProjectsViaTitleMenu(titleLabels: ["Changes", "更改"])
        }
        assertInProjects()

        // Open Workspace.
        app.buttons["project-row-Welcome"].tap()
        assertInWorkspace()

        // Code → Preview → Changes.
        tapTab(index: 1)
        tapTab(index: 2)
        tapTab(index: 3)

        // Back to Projects via the unified title menu (P0-1).
        backToProjectsViaTitleMenu(titleLabels: ["Changes", "更改"])
        assertInProjects()

        // Reopen Workspace.
        app.buttons["project-row-Welcome"].tap()
        assertInWorkspace()

        // Kill App → restore Session → still in the workspace.
        app.terminate()
        app.launch()
        assertInWorkspace()

        // Back to Projects again — the exit works after a restore, too.
        tapTab(index: 3)
        backToProjectsViaTitleMenu(titleLabels: ["Changes", "更改"])
        assertInProjects()
    }
}
