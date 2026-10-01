// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Expiry/ExpiryView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct ExpiryView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [ExpiryItem]

    private var stats: ExpiryStats { ExpiryStats(items: items) }

    var body: some View {
        VStack {
            statCard
        }
    }

    private var statCard: some View {
        HStack {
            Text("\(stats.expiringSoonCount)")
                .foregroundStyle(V32.amber)
            Text("\(stats.safeCount)")
                .foregroundStyle(V32.textSecondary)
        }
    }
}

private struct ExpiryRow: View {
    let item: ExpiryItem

    var body: some View {
        HStack {
            Text(item.name)
                .foregroundStyle(V32.textPrimary)
        }
    }
}
