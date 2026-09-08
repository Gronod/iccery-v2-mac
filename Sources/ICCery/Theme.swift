import SwiftUI

/// Design tokens carried over from the v1 stylesheet (docs/21 §Design tokens).
enum Theme {
    static let background = Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255)
    static let panel      = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x26 / 255)
    static let text       = Color(red: 0xd4 / 255, green: 0xd4 / 255, blue: 0xd4 / 255)
    static let accent     = Color(red: 0x00 / 255, green: 0x7a / 255, blue: 0xcc / 255)
    static let border     = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    /// v1 window/titlebar backing colour (docs/02 §Window contract).
    static let windowChrome = Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x22 / 255)

    enum Metrics {
        static let sidebarWidth: CGFloat = 270
        static let buttonSmall: CGFloat = 28
        static let buttonMedium: CGFloat = 36
        static let buttonLarge: CGFloat = 40
        static let cornerSmall: CGFloat = 4
        static let cornerMedium: CGFloat = 6
    }
}
