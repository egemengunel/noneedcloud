import AppKit
import SwiftUI

/// Colour tokens from the Figma file "NoNeedCloud · Apple UI/UX" (Renk/*).
/// The design is light-only; dark values are our own counterparts.
enum Theme {
    static let blue = Color.dynamic(light: 0x2457C6, dark: 0x78AAFF)
    static let ink = Color.dynamic(light: 0x121B2D, dark: 0xF2F5FA)
    static let muted = Color.dynamic(light: 0x4D5C71, dark: 0xA3AFC2)
    static let subtle = Color.dynamic(light: 0x64748B, dark: 0x8592A6)
    static let line = Color.dynamic(light: 0xE1E7EF, dark: 0x2E3A4F)
    static let lightLine = Color.dynamic(light: 0xEDF0F5, dark: 0x263247)
    static let surface = Color.dynamic(light: 0xF6F8FC, dark: 0x182235)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1C2638)
    static let window = Color.dynamic(light: 0xFFFFFF, dark: 0x121A2A)
    static let gray = Color.dynamic(light: 0xEDF1F7, dark: 0x263247)

    static let blueTint = Color.dynamic(light: 0xEAF1FF, dark: 0x1A2A4A)
    static let blueLine = Color.dynamic(light: 0xCBDCFF, dark: 0x2D4372)
    static let mint = Color.dynamic(light: 0xDDF4E9, dark: 0x173B2F)
    static let green = Color.dynamic(light: 0x18674F, dark: 0x6FD3AE)
    static let amber = Color.dynamic(light: 0x8C4A08, dark: 0xF0B56A)
    static let amberTint = Color.dynamic(light: 0xFFF1D8, dark: 0x3A2C14)
    static let amberLine = Color.dynamic(light: 0xF2DEB8, dark: 0x5A4421)
    static let red = Color.dynamic(light: 0xA93435, dark: 0xF08A8A)

    // The live-progress card is navy in both appearances.
    static let navy = Color(hex: 0x131E35)
    static let navy2 = Color(hex: 0x1D2B47)
    static let navyLine = Color(hex: 0x334767)
    static let lightBlue = Color(hex: 0xB7D1FF)
    static let lively = Color(hex: 0x78AAFF)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// The brand cloud mark (Marka / Bulut). Vector from Figma, tinted per use.
struct BrandCloud: View {
    var color: Color = Theme.ink
    var width: CGFloat = 96

    var body: some View {
        Image("BrandCloud")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(95.4042 / 65.9943, contentMode: .fit)
            .frame(width: width)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
