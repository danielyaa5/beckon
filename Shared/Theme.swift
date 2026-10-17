import SwiftUI
import AppKit

extension Color {
    /// Burnt orange from design 3, for fills behind white text.
    static let ringFill = Color(red: 0.76, green: 0.255, blue: 0.047)

    /// The same hue for text and icons: darker in light mode, lighter in dark
    /// mode, so it stays readable on both.
    static let ringText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(red: 1.0, green: 0.58, blue: 0.36, alpha: 1)
            : NSColor(red: 0.69, green: 0.23, blue: 0.04, alpha: 1)
    })
}

/// A small key label like the ones in menus: ⌘1, ⌃⌥⌘R.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
    }
}
