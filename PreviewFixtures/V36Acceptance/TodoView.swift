// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Todo/TodoView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct TodoView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var todos: [Todo]
    @Query private var memos: [Memo]

    private var list: [Todo] {
        todos.filter { !$0.isCompleted }
    }

    private var todayCount: Int { TodoFilter.todos(for: .today, in: todos).count }
    private var doneCount: Int { todos.filter(\.isCompleted).count }
    private var overdueCount: Int { TodoFilter.todos(for: .overdue, in: todos).count }

    var body: some View {
        VStack {
            header
            Text("\(todayCount)")
        }
    }

    private var header: some View {
        HStack {
            Text("待办")
                .foregroundStyle(V32.textPrimary)
            Text("\(doneCount)")
                .foregroundStyle(V32.textSecondary)
        }
    }
}
