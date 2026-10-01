// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Calendar/CalendarView.swift.
// Keeps identifiers + type structure; business logic removed.
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

    private var calendar: Calendar {
        var c = Calendar.current
        return c
    }

    @State private var selectedDate = Date()

    var body: some View {
        VStack {
            Text(selectedDate, format: .dateTime.year().month())
                .foregroundStyle(V32.textPrimary)
        }
    }
}
