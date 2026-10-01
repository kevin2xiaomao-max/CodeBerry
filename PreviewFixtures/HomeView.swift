import SwiftUI

/// §十七 3.0 验收主页.
/// 覆盖: computed subviews / helper funcs / 跨文件 View /
/// 设计令牌 / @State / Button / shapes / material / overlay+stroke / 深浅色.
struct HomeView: View {
    @State private var selectedTab = 0
    @State private var showRevenue = true

    var body: some View {
        VStack(spacing: 0) {
            V36HeaderView(title: "小掌柜")
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if showRevenue {
                        revenueHero
                    }
                    metricPair
                    V32SectionHeader(title: "今日待办")
                    todoList
                }
                .padding(.vertical)
            }
            V36FloatingTabBar(selected: selectedTab)
        }
    }

    /// computed subview: 顶部问候 + 切换按钮.
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("晚上好,老板")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(MockHomeData.userName + "的店铺")
                    .font(.system(size: HomeTokens.titleSize, weight: .bold))
            }
            Spacer()
            Button(showRevenue ? "隐藏营收" : "显示营收") {
                showRevenue.toggle()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(HomeTokens.brand)
            .foregroundStyle(.white)
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }

    /// computed subview: 营收 hero 卡 (shape 背景 + overlay 描边).
    var revenueHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日营收")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(MockHomeData.revenueToday)
                .font(.system(size: 34, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: HomeTokens.cardRadius)
                .fill(HomeTokens.brand.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: HomeTokens.cardRadius)
                .stroke(HomeTokens.brand, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    /// computed subview: 双卡片 (跨文件 V32 组件).
    var metricPair: some View {
        HStack(spacing: 12) {
            V32MetricCard(title: "待办", value: "3")
            V32MetricCard(title: "本周营收", value: "¥86,200")
        }
        .padding(.horizontal)
    }

    /// computed subview: 待办列表 (helper func 生成行).
    var todoList: some View {
        VStack(spacing: 4) {
            todoRow("进货", done: true)
            todoRow("对账", done: false)
            todoRow("回访客户", done: false)
        }
    }

    /// helper func: 待办行 (参数 + 三元表达式).
    func todoRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? HomeTokens.brand : .secondary)
            Text(title)
                .font(.system(size: 15))
            Spacer()
            if done {
                Text("已完成")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
