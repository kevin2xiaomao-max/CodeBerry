import SwiftUI

// CodeBerry / iPhone visual preview only.
// Static presentation mock based on XiaoZhangGui V3.6.1.
// No SwiftData, Repository, AI, navigation, or production data writes.

struct V36CodeBerryPreview: View {
    @State private var selectedTab = 0

    let brand = Color(red: 0.08, green: 0.30, blue: 0.24)
    let page = Color(red: 0.96, green: 0.96, blue: 0.95)

    var body: some View {
        ZStack(alignment: .bottom) {
            page.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    revenueHero
                    quickActions
                    contactsRail
                    metricPair
                    weekRail
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            floatingTabBar
                .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("晚上好")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("老板")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("9月30日 · 星期三")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                circleButton("cloud.sun")
                circleButton("bell")
            }
        }
    }

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日营业额")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            Text("¥ 680")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack {
                Text("较昨日 +12.6%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text("查看经营")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            pill("plus", "记一笔")
            pill("shippingbox", "商品")
            pill("ellipsis", "更多")
        }
    }

    private var contactsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近往来")
                .font(.headline)
            HStack(spacing: 14) {
                contact("＋", "新增")
                contact("8", "802房")
                contact("李", "李小姐")
                contact("陈", "陈先生")
            }
        }
    }

    private var metricPair: some View {
        HStack(spacing: 12) {
            metric("本月收入", "¥ 18,680", "经营累计")
            metric("月目标", "¥ 30,000", "已完成 62%")
        }
    }

    private var weekRail: some View {
        HStack(spacing: 6) {
            day("一", "28", false)
            day("二", "29", false)
            day("三", "30", true)
            day("四", "1", false)
            day("五", "2", false)
            day("六", "3", false)
            day("日", "4", false)
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            tab(0, "house", "首页")
            tab(1, "calendar", "日程")
            tab(2, "sparkles", "小掌柜")
            tab(3, "checkmark.circle", "待办")
            tab(4, "person", "我的")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 18)
    }

    private func circleButton(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.07), lineWidth: 1))
    }

    private func contact(_ initial: String, _ name: String) -> some View {
        VStack(spacing: 7) {
            Text(initial)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func metric(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func day(_ week: String, _ number: String, _ selected: Bool) -> some View {
        VStack(spacing: 5) {
            Text(week).font(.caption2.weight(.medium))
            Text(number).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(selected ? .white : .secondary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(selected ? brand : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tab(_ index: Int, _ icon: String, _ title: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                if selectedTab == index {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(selectedTab == index ? .white : .secondary)
            .padding(.horizontal, selectedTab == index ? 14 : 10)
            .padding(.vertical, 10)
            .background(selectedTab == index ? brand : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    V36CodeBerryPreview()
}
