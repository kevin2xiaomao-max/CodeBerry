// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Memo/MemoView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct MemoView: View {
    @Environment(\.modelContext) private var context
    @Query private var memos: [Memo]

    private var isMockPreview: Bool { RuntimeMode.allowsMockData }

    private var filtered: [Memo] {
        memos
    }

    var body: some View {
        VStack {
            memoList
        }
    }

    private var memoList: some View {
        ForEach(filtered, id: \.title) { memo in
            MemoCard(memo: memo)
        }
    }
}

struct MemoCard: View {
    let memo: Memo

    private var accentColor: Color {
        V32.brand
    }

    var body: some View {
        HStack {
            Text(memo.title)
                .foregroundStyle(V32.textPrimary)
        }
        .background(accentColor.opacity(0.08))
    }
}
