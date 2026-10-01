import SwiftUI

/// V32 设计系统组件 (§二跨文件自定义 View).
struct V32MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: HomeTokens.titleSize, weight: .bold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeTokens.brand.opacity(0.12))
        .cornerRadius(HomeTokens.cardRadius)
    }
}

/// 带强调色的行组件.
struct V32AccentRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(HomeTokens.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// 分组标题.
struct V32SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
