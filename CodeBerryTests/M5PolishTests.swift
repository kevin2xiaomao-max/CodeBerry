import XCTest
@testable import CodeBerry

/// M5: four-tab navigation polish — L10n completeness and session tab persistence.
final class M5PolishTests: XCTestCase {
    /// All M5 tab keys resolve to non-empty strings in both languages.
    func testTabL10nKeysExist() {
        let l10n = L10nService.shared
        let saved = l10n.language
        defer { l10n.language = saved }
        let keys: [L10nKey] = [.filesTab, .codeTab, .previewTab, .changesTab,
                               .previewNoFile, .previewNoFileHint]
        l10n.language = .zhHans
        for key in keys {
            XCTAssertFalse(l10n.t(key).isEmpty, "\(key) zh empty")
        }
        l10n.language = .english
        for key in keys {
            XCTAssertFalse(l10n.t(key).isEmpty, "\(key) en empty")
        }
    }

    /// The four tab titles are distinct.
    func testTabTitlesDistinct() {
        let l10n = L10nService.shared
        let titles = [l10n.t(.filesTab), l10n.t(.codeTab),
                      l10n.t(.previewTab), l10n.t(.changesTab)]
        XCTAssertEqual(Set(titles).count, 4, "tab titles must be distinct: \(titles)")
    }

    /// WorkspaceSession persists the selected tab across save/load.
    func testSessionPersistsSelectedTab() {
        let session = WorkspaceSession(projectFolder: "P", openFilePath: "/f.swift",
                                       cursorLines: [:], selectedTab: 2)
        SessionStore.save(session)
        let loaded = SessionStore.load()
        XCTAssertEqual(loaded.selectedTab, 2)
        // Clean up.
        SessionStore.clear()
        XCTAssertNil(SessionStore.load().projectFolder)
    }
}
