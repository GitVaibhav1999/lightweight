import SwiftUI
import CoreText
import UIKit

/// Trait-driven color: dark value in dark mode, chalk value in light (Light Mode Handoff §2).
func lwDyn(_ dark: UIColor, _ light: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}
func lwHex(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Court dark theme (Theme Options 1a): black ground, ball-green actions, court-blue AI voice, warm off-white ink.
enum LW {
    static let accent = lwDyn(lwHex(0xADBA5E), lwHex(0x566049))       // ball-green / earth-sage action
    static let accentSoft = lwDyn(lwHex(0xE4EBC0), lwHex(0x4A5340))
    static let accentPale = lwDyn(lwHex(0xF2F6DC), lwHex(0x3C4433))
    static let accentBright = lwDyn(lwHex(0xC7D584), lwHex(0x4A5340))   // --action-bright: BEST verdicts, record dots
    static let inkOnAccent = lwDyn(lwHex(0x141604), lwHex(0xF3EFE7))  // glyphs on action fills (chalk bolt in light)
    static let held = lwDyn(lwHex(0x869A69), lwHex(0x1C1A14, 0.4))    // HELD verdict: ink 40% on chalk
    static let bg = lwDyn(lwHex(0x0A0A08), lwHex(0xF3EFE7))           // design-board warm near-black / gym chalk
    static let ink = lwDyn(lwHex(0xE7E5D7), lwHex(0x1C1A14))          // warm off-white / warm ink
    static func ink(_ alpha: Double) -> Color { ink.opacity(alpha) }
    static func accent(_ alpha: Double) -> Color { accent.opacity(alpha) }
    static let glassFill = lwDyn(lwHex(0x787880, 0.16), lwHex(0xFFFFFF, 0.5))
    static let glassFillStrong = lwDyn(lwHex(0x787880, 0.18), lwHex(0xFFFFFF, 0.55))
    static let slideFill = lwDyn(lwHex(0x000000, 0.44), lwHex(0xFFFFFF, 0.5))   // slide bar dense fill
    static let hairline = lwDyn(lwHex(0xFFFFFF, 0.10), lwHex(0x1C1A14, 0.10))
    /// Elevation shadows: heavy black in dark, 12% ink in light (§2 glass row).
    static func shadow(_ dark: Double) -> Color { lwDyn(UIColor(white: 0, alpha: dark), lwHex(0x1C1A14, 0.12)) }
    static let screenPad: CGFloat = 10
    static let topPad: CGFloat = 58
}

enum LWFont {
    private static let wght = NSNumber(value: 0x77676874 as UInt32)
    private static let wdth = NSNumber(value: 0x77647468 as UInt32)

    /// Memoised: building a CTFont means a descriptor and a font instantiation, and a list
    /// asks for the same handful of faces once per text view per row. A 470-session history
    /// was doing that ~1,900 times a pass. The axes are the identity, so the key is exact.
    nonisolated(unsafe) private static var faces: [String: Font] = [:]

    /// Archivo variable font with explicit weight (100–900) and width (75–125) axes.
    static func archivo(_ size: CGFloat, weight: CGFloat = 400, width: CGFloat = 100) -> Font {
        let key = "\(size)|\(weight)|\(width)"
        if let f = faces[key] { return f }
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Archivo",
            kCTFontVariationAttribute: [wght: weight, wdth: width] as CFDictionary,
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        let font = Font(CTFontCreateWithFontDescriptor(desc, size, nil))
        faces[key] = font
        return font
    }
    /// Display: Archivo 900 at 85–90 % width — the big workout names.
    static func display(_ size: CGFloat, width: CGFloat = 88) -> Font { archivo(size, weight: 900, width: width) }
    static func heading(_ size: CGFloat, width: CGFloat = 90) -> Font { archivo(size, weight: 800, width: width) }
    static func body(_ size: CGFloat, weight: CGFloat = 400) -> Font { archivo(size, weight: weight, width: 100) }
    static func mono(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Regular", size: size)
    }
}

extension View {
    /// Small mono label: uppercase, letter-spaced — the eyebrow style used everywhere.
    func lwLabel(_ size: CGFloat = 10, tracking: CGFloat = 0.14, color: Color = LW.ink(0.3)) -> some View {
        self.font(LWFont.mono(size)).tracking(size * tracking).textCase(.uppercase).foregroundStyle(color)
    }
}
