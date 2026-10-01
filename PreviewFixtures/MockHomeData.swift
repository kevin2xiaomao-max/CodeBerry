import SwiftUI

/// §六设计令牌: 颜色 / 圆角 / 字号集中管理.
/// Inspector 里引用这些令牌的颜色会显示"此值来自设计令牌",
/// 并可选择只覆盖本次预览, 或直接修改这里的定义.
enum HomeTokens {
    static let brand = Color.green
    static let accent = Color.orange
    static let cardRadius: Double = 16
    static let titleSize: Double = 22
}

/// §七 Mock 数据: 首页示例数据, 也可作为 Mock 面板的手填参考.
enum MockHomeData {
    static let userName = "老板"
    static let revenueToday = "¥12,880"
    static let todoTitles = ["进货", "对账", "回访客户"]
}
