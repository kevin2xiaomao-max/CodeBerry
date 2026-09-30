import SwiftUI

/// Preview 2.0 smoke-test fixture.
///
/// NOT part of the app target — do not add to the .xcodeproj.
/// Paste the body (or the whole struct) into the in-app Editor's
/// Preview canvas after engine changes and confirm:
///   - no "Unknown identifier 'header'" / 'revenueHero' / 'quickActions' /
///     'contactsRail' / 'metricPair' / 'weekRail' / 'floatingTabBar' warnings
///   - rounded backgrounds, strokes, green hero, buttons and the floating
///     tab bar all render
///   - tapping a tab button visibly switches `selectedTab`
struct V36CodeBerryPreview: View {
    @State private var selectedTab = 0

    private let brand = Color.green
    private let ink = Color.primary
    private let paper = Color.white

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    revenueHero
                    quickActions
                    contactsRail
                    metricPair
                    weekRail
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .ignoresSafeArea()
            floatingTabBar
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("晚上好，老板")
                    .font(.title3.bold())
                    .foregroundStyle(ink)
                Text("今日经营一览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            circleButton("bell")
            circleButton("gearshape")
        }
    }

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本月收入")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            Text("¥ 18,680")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
            Text("较上月 +12.4%")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(20)
        .background(brand, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            pill("plus", "记一笔")
            pill("qrcode", "收款码")
            pill("chart.bar", "报表")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contactsRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常联系人")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    contact("陈", "供应商")
                    contact("李", "老客户")
                    contact("王", "合伙人")
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var metricPair: some View {
        HStack(spacing: 12) {
            metric("今日订单", "36", "单")
            metric("待办事项", "5", "件")
        }
    }

    private var weekRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周")
                .font(.headline)
            HStack(spacing: 8) {
                day("一", "28", false)
                day("二", "29", false)
                day("三", "30", true)
                day("四", "1", false)
                day("五", "2", false)
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            tab(0, "house", "首页")
            tab(1, "list.bullet", "待办")
            tab(2, "chart.pie", "经营")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func circleButton(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.body)
            .foregroundStyle(ink)
            .frame(width: 42, height: 42)
            .background(paper, in: Circle())
            .overlay(
                Circle()
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(brand, in: Capsule())
    }

    private func contact(_ name: String, _ role: String) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(brand.opacity(0.85), in: Circle())
            Text(role)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.title.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func day(_ weekday: String, _ date: String, _ isToday: Bool) -> some View {
        VStack(spacing: 6) {
            Text(weekday)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isToday ? .white : .secondary)
            Text(date)
                .font(.headline)
                .foregroundStyle(isToday ? .white : ink)
        }
        .frame(width: 48, height: 64)
        .background(
            isToday ? brand : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func tab(_ index: Int, _ icon: String, _ title: String) -> some View {
        let selected = selectedTab == index
        return Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                if selected {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(selected ? brand : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                selected ? brand.opacity(0.12) : Color.clear,
                in: Capsule()
            )
        }
    }
}
