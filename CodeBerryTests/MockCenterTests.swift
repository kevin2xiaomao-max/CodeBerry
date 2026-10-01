import XCTest
@testable import CodeBerry

/// §三十九: MockCenter — 项目级 Mock + profile, 永不执行真实副作用.
@MainActor
final class MockCenterTests: XCTestCase {
    func testBuiltInProfilesExist() {
        let center = MockCenter()
        let names = center.profiles.map(\.displayName)
        // §17: Home / Normal, Home / Empty, Home / Busy, Home / Dark.
        XCTAssertTrue(names.contains("Home / Normal"))
        XCTAssertTrue(names.contains("Home / Empty"))
        XCTAssertTrue(names.contains("Home / Busy"))
        XCTAssertTrue(names.contains("Home / Dark"))
        XCTAssertEqual(center.activeProfile?.displayName, "Home / Normal")
    }

    func testQualifiedKeyBeatsBareKey() {
        let center = MockCenter()
        center.setValue(.string("bare"), view: "", property: "userName")
        center.setValue(.string("qualified"), view: "HomeView", property: "userName")
        // Qualified key wins for its own view...
        XCTAssertEqual(center.value(view: "HomeView", property: "userName")?.text, "qualified")
        // ...other views fall back to the bare key.
        XCTAssertEqual(center.value(view: "OtherView", property: "userName")?.text, "bare")
    }

    func testProfileSwitchChangesValues() {
        let center = MockCenter()
        XCTAssertEqual(center.value(view: "HomeView", property: "todoCount")?.text, "7")
        center.activeProfileID = center.profiles.first { $0.displayName == "Home / Empty" }?.id
        XCTAssertEqual(center.value(view: "HomeView", property: "todoCount")?.text, "0")
        center.activeProfileID = center.profiles.first { $0.displayName == "Home / Busy" }?.id
        XCTAssertEqual(center.value(view: "HomeView", property: "todoCount")?.text, "42")
    }

    func testDarkProfileFlag() {
        let center = MockCenter()
        center.activeProfileID = center.profiles.first { $0.displayName == "Home / Dark" }?.id
        XCTAssertEqual(center.activeProfile?.darkMode, true)
    }

    func testAddAndRemoveProfile() {
        let center = MockCenter()
        let count = center.profiles.count
        center.addProfile(named: "Test")
        XCTAssertEqual(center.profiles.count, count + 1)
        XCTAssertEqual(center.activeProfile?.displayName, "Test")
        // 新 profile 继承当前值.
        XCTAssertNotNil(center.value(view: "HomeView", property: "revenue"))
        center.removeProfile(id: center.activeProfileID!)
        XCTAssertEqual(center.profiles.count, count)
    }

    func testApplyPushesToMockStoreWithoutSideEffects() {
        let center = MockCenter()
        let store = PreviewMockStore()
        center.apply(to: store)
        // store 拿到纯数据.
        XCTAssertEqual(store.value(for: "HomeView.userName")?.display, "老板")
        XCTAssertEqual(store.value(for: "userName")?.display, "老板")
    }

    func testMockValueKinds() {
        XCTAssertEqual(MockValue.int(3).previewValue().display, "3")
        XCTAssertEqual(MockValue.double(1.5).previewValue().display, "1.5")
        XCTAssertEqual(MockValue.bool(true).previewValue().display, "true")
        XCTAssertEqual(MockValue.string("x").previewValue().display, "x")
    }
}
