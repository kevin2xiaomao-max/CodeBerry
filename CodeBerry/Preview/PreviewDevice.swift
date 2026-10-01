import SwiftUI

// MARK: - §四 Device presets

/// Canvas-only device presets. Sizes are reasonable viewports in points
/// (§四: 没有精确设备尺寸就用合理 viewport).
struct PreviewDevicePreset: Identifiable, Hashable {
    let id: String
    let width: CGFloat
    let height: CGFloat
    /// Approximate safe-area insets (top, bottom) in points, portrait.
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var nameKey: L10nKey {
        switch id {
        case "air": return .deviceIPhoneAir
        case "promax": return .deviceIPhoneProMax
        case "compact": return .deviceCompactIPhone
        case "ipad": return .deviceIPad
        default: return .deviceIPhonePro
        }
    }

    static let iPhoneAir = PreviewDevicePreset(id: "air", width: 420, height: 912, safeTop: 59, safeBottom: 34)
    static let iPhonePro = PreviewDevicePreset(id: "pro", width: 402, height: 874, safeTop: 59, safeBottom: 34)
    static let iPhoneProMax = PreviewDevicePreset(id: "promax", width: 440, height: 956, safeTop: 59, safeBottom: 34)
    static let compactIPhone = PreviewDevicePreset(id: "compact", width: 375, height: 667, safeTop: 20, safeBottom: 0)
    static let iPad = PreviewDevicePreset(id: "ipad", width: 820, height: 1180, safeTop: 24, safeBottom: 20)

    static let all: [PreviewDevicePreset] = [.iPhoneAir, .iPhonePro, .iPhoneProMax, .compactIPhone, .iPad]
}

enum PreviewOrientation: String, CaseIterable {
    case portrait
    case landscape

    var key: L10nKey {
        switch self {
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}

// MARK: - §五 Light / Dark (canvas-only)

/// Canvas-only appearance (§五: 仅影响预览画布，不影响 App).
enum PreviewAppearance: String, CaseIterable {
    case followSystem
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .followSystem: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var key: L10nKey {
        switch self {
        case .followSystem: return .followSystem
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Per-canvas settings: device, orientation, safe-area overlay, appearance.
@Observable
final class PreviewCanvasSettings: @unchecked Sendable {
    /// Shared instance so the Settings screen and the canvas stay in sync.
    static let shared = PreviewCanvasSettings()

    var device: PreviewDevicePreset = .iPhonePro
    var orientation: PreviewOrientation = .portrait
    var showSafeArea = true

    /// Canvas-only appearance (§五), persisted and shared with Settings.
    var appearance: PreviewAppearance {
        get {
            PreviewAppearance(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "")
                ?? .followSystem
        }
        set {
            // Computed properties don't auto-notify under @Observable.
            _$observationRegistrar.withMutation(of: self, keyPath: \.appearance) {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearanceKey)
            }
        }
    }

    static let appearanceKey = "previewAppearance"

    /// Portrait point size of the device surface.
    var deviceSize: CGSize {
        switch orientation {
        case .portrait: return CGSize(width: device.width, height: device.height)
        case .landscape: return CGSize(width: device.height, height: device.width)
        }
    }

    /// Safe-area insets adjusted for orientation.
    var safeInsets: EdgeInsets {
        switch orientation {
        case .portrait:
            return EdgeInsets(top: device.safeTop, leading: 0, bottom: device.safeBottom, trailing: 0)
        case .landscape:
            return EdgeInsets(top: 0, leading: device.safeTop, bottom: 0, trailing: device.safeTop)
        }
    }
}
