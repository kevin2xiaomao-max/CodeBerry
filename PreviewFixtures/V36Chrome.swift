import SwiftUI

/// V36 风格 chrome (§二跨文件): 顶栏 + 悬浮底栏.
struct V36HeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Image(systemName: "bell")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }
}

/// 悬浮毛玻璃底栏. selected 由调用方 @State 传入, 点选高亮品牌色.
struct V36FloatingTabBar: View {
    let selected: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton("首页", index: 0)
            tabButton("待办", index: 1)
            tabButton("日历", index: 2)
            tabButton("经营", index: 3)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// helper func: 单个 tab 按钮.
    func tabButton(_ title: String, index: Int) -> some View {
        Button(title) {}
            .foregroundStyle(selected == index ? HomeTokens.brand : .secondary)
            .font(.system(size: 14, weight: selected == index ? .semibold : .regular))
            .frame(maxWidth: .infinity)
    }
}
