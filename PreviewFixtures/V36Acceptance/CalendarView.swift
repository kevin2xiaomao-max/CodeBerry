// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Calendar/CalendarView.swift.
// Keeps identifiers + type structure; business logic removed.
// NOT compiled by Xcode — parsed by SwiftParser in acceptance tests only.
import SwiftData
import SwiftUI

struct CalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var todos: [Todo]
    @Query private var performances: [Performance]
    @Query private var expenses: [Expense]
    @Query private var expiryItems: [ExpiryItem]
    @Query private var customers: [CustomerRequest]
    @Query private var memos: [Memo]

    /// 周日为一周起点（对齐 Android firstDayOfWeek = 0）
    private var calendar: Calendar {
        var c = Calendar.current
        return c
    }

    @State private var currentMonth = Date()
    @State private var selectedDate = Date()

    private var dayNumber: Int {
        Calendar.current.component(.day, from: selectedDate)
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
    }

    private var monthDayCount: Int {
        calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
    }

    var body: some View {
        VStack {
            Text(selectedDate, format: .dateTime.year().month())
            Text("第 \(dayNumber) 天")
            Text("本月 \(monthDayCount) 天")
        }
        .foregroundStyle(V32.textPrimary)
    }
}
