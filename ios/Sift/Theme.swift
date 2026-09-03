import SwiftUI

/// Every colour and type style in the app. Retheming happens here and nowhere else.
enum Theme {

    // MARK: Ground

    static let paper = dynamic(light: 0xFBF9F4, dark: 0x131211)
    static let paperRaised = dynamic(light: 0xFFFFFF, dark: 0x1D1B19)
    static let ink = dynamic(light: 0x1A1815, dark: 0xF2EEE6)
    static let inkSoft = dynamic(light: 0x6B6357, dark: 0x9C948A)
    static let inkFaint = dynamic(light: 0x9C9488, dark: 0x6E675E)
    static let rule = dynamic(light: 0xE3DDD1, dark: 0x2E2B27)

    // MARK: Item accents
    //
    // Desaturated so they can sit inside body text without vibrating, and far
    // enough apart in hue to stay separable at chip size. Colour is never the
    // only signal — chips always carry a count and a glyph too.

    static let event = dynamic(light: 0x3A4E8C, dark: 0x8FA3E0)     // ink indigo
    static let task = dynamic(light: 0x9A6B1E, dark: 0xD8A854)      // ochre
    static let backlog = dynamic(light: 0x9E4F3A, dark: 0xD98B72)   // clay
    static let note = dynamic(light: 0x5A7355, dark: 0x9DBA96)      // sage

    static func accent(for kind: ItemKind) -> Color {
        switch kind {
        case .event: return event
        case .task: return task
        case .backlog: return backlog
        case .note: return note
        }
    }

    // MARK: Type

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let display = serif(30, .semibold)
    static let heading = serif(21, .semibold)
    static let body = Font.system(size: 16)
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 13, design: .monospaced)

    // MARK: Helper

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

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

/// A hairline divider that matches the editorial rules used across the app.
struct Rule: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 0.5)
    }
}
