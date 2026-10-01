// V36Acceptance fixture — desensitized from XiaoZhangGui/Demo/DemoMode.swift.
// Keeps identifiers + type structure; business logic removed.
// NOT compiled by Xcode — parsed by SwiftParser in acceptance tests only.
import Foundation

/// 演示模式开关（脱敏：UserDefaults 持久化细节已移除）。
@Observable
@MainActor
final class DemoMode {
    static let shared = DemoMode()
    static let userDefaultsKey = "xzg_demo_mode_enabled"

    var isEnabled: Bool = false
    var sessionID: UUID = UUID()

    private init() {}

    func resetDemoData() {
        sessionID = UUID()
    }
}

/// 演示数据目录（脱敏：仅保留验收所需的静态数值）。
@MainActor
enum DemoCatalog {
    static let monthlyRevenue = 68_400.0
    static let monthlyGoal = 120_000.0
}
