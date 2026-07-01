import AppKit
import SwiftUI

/// "Warm Night" palette — single source of truth for both AppKit (NSColor) and
/// SwiftUI (Color) so the menu-bar popover, settings, and break overlay match
/// the design doc (`SoftFocus Estados.dc.html`) exactly.
enum Theme {
    // Hex from the design doc's CSS custom properties.
    static let bgTop = hex(0x2c2014)
    static let bgMid = hex(0x1a130c)
    static let bgBot = hex(0x120c07)
    static let panel = hex(0x1e1812)
    static let panel2 = hex(0x251e16)
    static let pop = hex(0x221b14)
    static let track = hex(0x3a2f24)
    static let text = hex(0xf4ece2)
    static let text2 = hex(0xb6a493)
    static let text3 = hex(0x82715f)
    static let accent = hex(0xe7a468)
    static let btnText = hex(0x2a1606)
    static let border = NSColor(white: 1, alpha: 0.09)          // rgba(255,238,214,0.09) ≈ warm white 9%
    static let accentDim = accent.withAlphaComponent(0.16)

    // SwiftUI mirrors.
    static var bgTopC: Color { Color(bgTop) }
    static var bgMidC: Color { Color(bgMid) }
    static var bgBotC: Color { Color(bgBot) }
    static var panelC: Color { Color(panel) }
    static var panel2C: Color { Color(panel2) }
    static var trackC: Color { Color(track) }
    static var textC: Color { Color(text) }
    static var text2C: Color { Color(text2) }
    static var text3C: Color { Color(text3) }
    static var accentC: Color { Color(accent) }
    static var btnTextC: Color { Color(btnText) }
    static var borderC: Color { Color(white: 1, opacity: 0.09) }
    static var accentDimC: Color { accentC.opacity(0.16) }

    static func hex(_ v: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: 1
        )
    }
}
