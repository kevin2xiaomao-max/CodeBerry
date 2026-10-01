// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Home/HomeView.swift.
// Keeps identifiers + type structure; business logic removed.
// The six acceptance identifiers are preserved verbatim:
// DemoMode, greetingPrefix, V32, ownerDisplayName, handlingItems, Calendar.
// NOT compiled by Xcode — parsed by SwiftParser in acceptance tests only.
import Charts
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Bindable private var demo = DemoMode.shared
    @Query private var todos: [Todo]
    @Query private var performances: [Performance]
    @Query private var expiryItems: [ExpiryItem]
    @Query private var customers: [CustomerRequest]
    @Query private var memos: [Memo]

    private var summary: TodaySummary {
        TodaySummary.build(performances: performances, todos: todos, customers: customers, expiryItems: expiryItems)
    }

    private var monthRevenue: Double {
        if demo.isEnabled { return DemoCatalog.monthlyRevenue }
        return 0
    }

    private var monthGoal: Double {
        demo.isEnabled ? DemoCatalog.monthlyGoal : settings.monthGoal
    }

    private var handlingItems: [HomeInboxItem] {
        return HomeInbox.items(todos: summary.todos, deliveries: summary.deliveries,
                               expiryItems: summary.pendingExpiry, limit: 3)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !handlingItems.isEmpty {
                    Text("\(handlingItems.count)")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greetingPrefix)
                .foregroundStyle(V32.textSecondary)
            Text(ownerDisplayName)
                .foregroundStyle(V32.textPrimary)
            Text(Date(), format: .dateTime.month().day())
        }
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "早上好" }
        if hour < 14 { return "中午好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    private var ownerDisplayName: String {
        let name = settings.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "老板" : name
    }

    private var weekRail: some View {
        let calendar = Calendar.current
        let today = Date()
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return HStack(spacing: 6) {
            ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                Text(date, format: .dateTime.day())
            }
        }
    }
}

struct HomeActionRow: View {
    let item: HomeInboxItem

    var body: some View {
        HStack {
            Text(item.title)
                .foregroundStyle(V32.textPrimary)
            Text(item.time)
                .foregroundStyle(V32.textTertiary)
        }
    }
}
