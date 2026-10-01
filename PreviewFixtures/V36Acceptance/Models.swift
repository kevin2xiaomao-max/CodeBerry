// V36Acceptance fixture — desensitized model + helper layer.
// Real sources: XiaoZhangGui/Models/*.swift, XiaoZhangGui/Utilities/DisplayLogic.swift,
// XiaoZhangGui/Features/Home/TodaySummary.swift. Keeps identifiers + type structure;
// business logic removed. NOT compiled by Xcode — parsed by SwiftParser only.
import Foundation
import SwiftData

// MARK: - @Model stubs (fields referenced by the acceptance views)

@Model
final class Todo {
    var title: String = ""
    var detail: String = ""
    var dueDate: Date?
    var priority: Int = 0
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
    var notificationID: String = UUID().uuidString

    init(title: String = "", isCompleted: Bool = false) {
        self.title = title
        self.isCompleted = isCompleted
    }
}

@Model
final class Performance {
    var amount: Double = 0
    var note: String = ""
    var date: Date = Date()

    init(amount: Double = 0, date: Date = Date()) {
        self.amount = amount
        self.date = date
    }
}

@Model
final class Expense {
    var amount: Double = 0
    var category: String = ""
    var date: Date = Date()

    init(amount: Double = 0, date: Date = Date()) {
        self.amount = amount
        self.date = date
    }
}

@Model
final class ExpiryItem {
    var name: String = ""
    var expiryDate: Date = Date()
    var notificationID: String = UUID().uuidString

    init(name: String = "") {
        self.name = name
    }
}

@Model
final class CustomerRequest {
    var title: String = ""
    var notificationID: String = UUID().uuidString

    var displayTitle: String { title }

    init(title: String = "") {
        self.title = title
    }
}

@Model
final class Memo {
    var title: String = ""
    var content: String = ""
    var updatedAt: Date = Date()

    init(title: String = "") {
        self.title = title
    }
}

// MARK: - Home support types (real: XiaoZhangGui/Utilities/DisplayLogic.swift)

struct HomeInboxItem: Identifiable {
    enum Route { case todo, customer, expiry }
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let route: Route
}

enum HomeInbox {
    static func items(todos: [Todo], deliveries: [CustomerRequest],
                      expiryItems: [ExpiryItem], limit: Int) -> [HomeInboxItem] {
        []
    }
}

struct TodaySummary {
    var todos: [Todo] = []
    var deliveries: [CustomerRequest] = []
    var pendingExpiry: [ExpiryItem] = []

    static func build(performances: [Performance], todos: [Todo],
                      customers: [CustomerRequest], expiryItems: [ExpiryItem]) -> TodaySummary {
        TodaySummary()
    }
}

// MARK: - App settings (real: @Environment(AppSettings.self))

@Observable
final class AppSettings {
    var ownerName: String = ""
    var monthGoal: Double = 0
}

// MARK: - Todo helpers (real: XiaoZhangGui/Features/Todo/TodoModel.swift)

enum TodoFilter {
    static func todos(for scope: TodoScope, in todos: [Todo]) -> [Todo] { [] }
}

enum TodoScope { case today, overdue }

// MARK: - Expiry helpers (real: XiaoZhangGui/Features/Expiry/ExpiryModel.swift)

struct ExpiryStats {
    let expiringSoonCount: Int
    let urgentCount: Int
    let warningCount: Int
    let safeCount: Int

    init(items: [ExpiryItem]) {
        expiringSoonCount = 0
        urgentCount = 0
        warningCount = 0
        safeCount = 0
    }
}

// MARK: - Runtime mode (real: XiaoZhangGui/.../RuntimeMode)

enum RuntimeMode {
    static var allowsMockData: Bool { false }
}
