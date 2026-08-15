//
//  Theme.swift
//  AppX Manager
//

import SwiftUI

/// Design tokens ported 1:1 from `design/AppX Manager.dc.html`'s light/dark palettes.
enum Theme {
    struct Palette {
        let pageBackground: Color
        let windowBackground: Color
        let titlebarBackground: Color
        let sidebarBackground: Color
        let text: Color
        let textSecondary: Color
        let textTertiary: Color
        let border: Color
        let borderStrong: Color
        let rowHover: Color
        let rowSelectedBackground: Color
        let accent: Color
        let accentText: Color
        let danger: Color
        let tagBackground: Color
        let inputBackground: Color
        let panelBackground: Color
        let chipBackground: Color
    }

    static let light = Palette(
        pageBackground: Color(hex: 0xECEEEF),
        windowBackground: Color(hex: 0xFFFFFF),
        titlebarBackground: Color(hex: 0xF6F6F8, opacity: 0.92),
        sidebarBackground: Color(hex: 0xF6F7F9, opacity: 0.85),
        text: Color(hex: 0x1D1D1F),
        textSecondary: Color(hex: 0x6E6E73),
        textTertiary: Color(hex: 0x98989D),
        border: Color.black.opacity(0.08),
        borderStrong: Color.black.opacity(0.12),
        rowHover: Color.black.opacity(0.025),
        rowSelectedBackground: Color(hex: 0x229D5A, opacity: 0.09),
        accent: Color(hex: 0x1F9D55),
        accentText: Color(hex: 0xFFFFFF),
        danger: Color(hex: 0xE0392F),
        tagBackground: Color.black.opacity(0.045),
        inputBackground: Color.black.opacity(0.045),
        panelBackground: Color(hex: 0xFBFBFC),
        chipBackground: Color.black.opacity(0.05)
    )

    static let dark = Palette(
        pageBackground: Color(hex: 0x000000),
        windowBackground: Color(hex: 0x1E1E1E),
        titlebarBackground: Color(hex: 0x282828, opacity: 0.9),
        sidebarBackground: Color(hex: 0x1C1C1E, opacity: 0.72),
        text: Color(hex: 0xF5F5F7),
        textSecondary: Color(hex: 0x98989D),
        textTertiary: Color(hex: 0x6E6E73),
        border: Color.white.opacity(0.09),
        borderStrong: Color.white.opacity(0.14),
        rowHover: Color.white.opacity(0.04),
        rowSelectedBackground: Color(hex: 0x30D158, opacity: 0.14),
        accent: Color(hex: 0x30D158),
        accentText: Color(hex: 0x0B3D1C),
        danger: Color(hex: 0xFF453A),
        tagBackground: Color.white.opacity(0.08),
        inputBackground: Color.white.opacity(0.08),
        panelBackground: Color(hex: 0x242426),
        chipBackground: Color.white.opacity(0.09)
    )

    static func palette(for colorScheme: ColorScheme) -> Palette {
        colorScheme == .dark ? dark : light
    }

    /// Fixed per-source tag colors — identical across light/dark (spec §6).
    enum SourceColor {
        static let appStore = Color(hex: 0x0A84FF)
        static let homebrew = Color(hex: 0xFF9F0A)
        static let directDownload = Color(hex: 0xBF5AF2)
        static let devTools = Color(hex: 0x5E5CE6)
    }

    /// Grid/sizing metrics from the design (spec §6).
    enum Layout {
        static let sidebarWidth: CGFloat = 216
        static let detailPanelWidth: CGFloat = 360
        static let defaultWindowSize = CGSize(width: 1360, height: 860)

        static let rowCheckboxWidth: CGFloat = 32
        static let rowIconWidth: CGFloat = 34
        static let rowInstalledWidth: CGFloat = 100
        static let rowLatestWidth: CGFloat = 100
        static let rowActionWidth: CGFloat = 190
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
