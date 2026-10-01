// V36Acceptance fixture — desensitized from XiaoZhangGui/DesignSystem/V32/V32Color.swift.
// Keeps identifiers + type structure; theme-store derivations replaced with fixed values.
// NOT compiled by Xcode — parsed by SwiftParser in acceptance tests only.
import SwiftUI

enum V32 {
    // MARK: 背景层级（脱敏：原派生自 ThemeStore.backgroundPalette）
    @MainActor static var pageBG: Color { Color.gray.opacity(0.08) }
    @MainActor static var pageBGSecondary: Color { Color.gray.opacity(0.12) }
    @MainActor static var card: Color { Color.white }
    @MainActor static var cardElevated: Color { Color.white }
    @MainActor static var cardInset: Color { Color.gray.opacity(0.06) }
    @MainActor static var cardOutline: Color { Color.gray.opacity(0.2) }

    // MARK: 主视觉（固定不随主题）
    static let hero = Color(red: 0.12, green: 0.17, blue: 0.14)
    static let heroGlow = Color(red: 0.17, green: 0.24, blue: 0.2)

    // MARK: Accent（脱敏：原派生自 ThemeStore.accentPalette）
    @MainActor static var brand: Color { Color.green }
    static let brandOnHero = Color(red: 0.31, green: 0.75, blue: 0.53)
    @MainActor static var brandSoft: Color { Color.green.opacity(0.12) }
    static let brandSoftOnHero = Color(red: 0.16, green: 0.24, blue: 0.2)

    // MARK: 功能色（语义固定不随主题）
    static let amber = Color(red: 0.75, green: 0.54, blue: 0.18)
    static let amberSoft = Color(red: 0.97, green: 0.93, blue: 0.85)
    static let amberOnHero = Color(red: 0.94, green: 0.69, blue: 0.3)

    // MARK: 文本层级（脱敏：原派生自 ThemeStore）
    @MainActor static var textPrimary: Color { Color.primary }
    @MainActor static var textSecondary: Color { Color.secondary }
    @MainActor static var textTertiary: Color { Color.secondary.opacity(0.7) }
    @MainActor static var textQuaternary: Color { Color.secondary.opacity(0.5) }
}
