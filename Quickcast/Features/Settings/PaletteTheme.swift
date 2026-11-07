import AppKit
import SwiftUI

/// Quickcast fork: a colour scheme for the palette, laid over its glass; `.standard` adds nothing.
enum PaletteTheme: String, CaseIterable, Identifiable, Sendable {
    case standard
    case dracula
    case catppuccinMocha
    case catppuccinLatte
    case nord
    case tokyoNight
    case gruvbox
    case oneDark
    case rosePine
    case solarizedLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "Default")
        case .dracula: "Dracula"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .catppuccinLatte: "Catppuccin Latte"
        case .nord: "Nord"
        case .tokyoNight: "Tokyo Night"
        case .gruvbox: "Gruvbox"
        case .oneDark: "One Dark"
        case .rosePine: "Rosé Pine"
        case .solarizedLight: "Solarized Light"
        }
    }

    /// Background and accent as sRGB hex, from each scheme's published palette.
    private var hex: (background: UInt32, accent: UInt32)? {
        switch self {
        case .standard: nil
        case .dracula: (0x282A36, 0xBD93F9)
        case .catppuccinMocha: (0x1E1E2E, 0xCBA6F7)
        case .catppuccinLatte: (0xEFF1F5, 0x8839EF)
        case .nord: (0x2E3440, 0x88C0D0)
        case .tokyoNight: (0x1A1B26, 0x7AA2F7)
        case .gruvbox: (0x282828, 0xFABD2F)
        case .oneDark: (0x282C34, 0x61AFEF)
        case .rosePine: (0x191724, 0xEBBCBA)
        case .solarizedLight: (0xFDF6E3, 0x268BD2)
        }
    }

    var isLight: Bool { self == .catppuccinLatte || self == .solarizedLight }

    /// Strong enough to read as the scheme, light enough that the glass still shows through.
    var glassTint: Color? { hex.map { Self.color($0.background).opacity(0.82) } }

    var accent: Color? { hex.map { Self.color($0.accent) } }

    /// The scheme decides light or dark, so the ink ramps keep their contrast against it.
    var nsAppearance: NSAppearance? {
        guard hex != nil else { return nil }
        return NSAppearance(named: isLight ? .aqua : .darkAqua)
    }

    /// Two swatches for the picker: background, then accent.
    var swatches: [Color] {
        guard let hex else { return [] }
        return [Self.color(hex.background), Self.color(hex.accent)]
    }

    private static func color(_ value: UInt32) -> Color {
        Color(
            .sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
