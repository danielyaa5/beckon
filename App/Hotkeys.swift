import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Rings the chosen device (or the first favorite) from anywhere.
    static let ringFavorite = Self("ringFavorite", initial: .init(.r, modifiers: [.control, .option, .command]))
    /// Opens the Spotlight-style ring palette.
    static let openPalette = Self("openPalette", initial: .init(.space, modifiers: [.control, .option]))
}

/// Global shortcut keys (Carbon hot keys through KeyboardShortcuts, so they
/// need no Accessibility permission). Changed in the window's Settings.
@MainActor
enum Hotkeys {
    static func install() {
        KeyboardShortcuts.onKeyUp(for: .ringFavorite) {
            Task { await AppModel.shared.ringHotkeyTarget() }
        }
        KeyboardShortcuts.onKeyUp(for: .openPalette) {
            RingPalette.shared.toggle()
        }
        syncText()
    }

    /// Keeps the shared settings' copy of the ring shortcut current, for the
    /// menu and the widgets.
    static func syncText() {
        AppModel.shared.setHotkeyText(text(for: .ringFavorite))
    }

    static func text(for name: KeyboardShortcuts.Name) -> String? {
        KeyboardShortcuts.getShortcut(for: name)?.description
    }
}
