// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Performance/PerformanceView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct PerformanceView: View {
    @Environment(\.modelContext) private var context
    @Query private var performances: [Performance]
    @Query private var expenses: [Expense]

    private var todayRevenue: Double {
        0
    }

    private var yesterdayRevenue: Double {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return 0
    }

    private var monthRevenue: Double {
        performances.filter { $0.date >= Date() }.reduce(0) { $0 + $1.amount }
    }

    private var yearRevenue: Double {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date())) ?? Date()
        return performances.filter { $0.date >= start }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack {
            Text("\(todayRevenue)")
                .foregroundStyle(V32.textPrimary)
            Text("\(monthRevenue)")
                .foregroundStyle(V32.textSecondary)
        }
    }
}
