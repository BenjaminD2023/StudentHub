import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum HubPalette {
    static let background = Color.hubBackground
    static let sidebar = Color.hubSidebar
    static let grouped = Color.hubGrouped
    static let selected = Color.hubGroupedSecondary
    static let separator = Color.hubSeparator
    static let hubAccent = Color.hubAccent
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.68)
    static let success = Color(red: 0.20, green: 0.67, blue: 0.38)
    static let red = Color(red: 0.90, green: 0.26, blue: 0.27)
    static let yellow = Color(red: 0.95, green: 0.67, blue: 0.15)
}

struct HubProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 30)
            .background(configuration.isPressed ? HubPalette.hubAccent.opacity(0.78) : HubPalette.hubAccent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

extension Color {
    static var hubBackground: Color {
        #if os(macOS)
        Color(nsColor: dynamicMacColor(light: 0xF7F8FA, dark: 0x111318))
        #else
        Color(uiColor: dynamicIOSColor(light: 0xF7F8FA, dark: 0x111318))
        #endif
    }

    static var hubSidebar: Color {
        #if os(macOS)
        Color(nsColor: dynamicMacColor(light: 0xEEF1F5, dark: 0x171A20))
        #else
        Color(uiColor: dynamicIOSColor(light: 0xEEF1F5, dark: 0x171A20))
        #endif
    }

    static var hubGrouped: Color {
        #if os(macOS)
        Color(nsColor: dynamicMacColor(light: 0xFFFFFF, dark: 0x1B1E25))
        #else
        Color(uiColor: dynamicIOSColor(light: 0xFFFFFF, dark: 0x1B1E25))
        #endif
    }

    static var hubGroupedSecondary: Color {
        #if os(macOS)
        Color(nsColor: dynamicMacColor(light: 0xE7ECF4, dark: 0x252B36))
        #else
        Color(uiColor: dynamicIOSColor(light: 0xE7ECF4, dark: 0x252B36))
        #endif
    }

    static var hubSeparator: Color {
        #if os(macOS)
        Color(nsColor: dynamicMacColor(light: 0xD9DFE8, dark: 0x343A45))
        #else
        Color(uiColor: dynamicIOSColor(light: 0xD9DFE8, dark: 0x343A45))
        #endif
    }

    static var hubAccent: Color { Color(red: 0.12, green: 0.43, blue: 0.93) }

    #if os(macOS)
    private static func dynamicMacColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light)
        }
    }
    #else
    private static func dynamicIOSColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) }
    }
    #endif
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

extension View {
    func hubPanel(cornerRadius: CGFloat = 12) -> some View {
        background(Color.hubGrouped)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.hubSeparator.opacity(0.72), lineWidth: 1)
            }
    }

    func hubPage() -> some View {
        background(Color.hubBackground.ignoresSafeArea())
    }
}
