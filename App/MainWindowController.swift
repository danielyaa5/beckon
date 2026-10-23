import AppKit
import SwiftUI

/// The main window (design 5's layout). The app normally lives only in the
/// menu bar with no Dock icon, like NordVPN: opening this window brings the
/// Dock icon and ⌘-Tab entry, closing it takes them away again (unless
/// Settings says to keep the Dock icon).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show(_ section: WindowSection? = nil) {
        if let section { AppModel.shared.section = section }
        let window = self.window ?? make()
        self.window = window
        DockPolicy.windowOpened()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        AppModel.shared.willAppear()
    }

    func windowWillClose(_ notification: Notification) {
        DockPolicy.windowClosed()
    }

    private func make() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Beckon"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: MainWindow().environmentObject(AppModel.shared))
        // The window keeps its own size. By default the hosting controller
        // sizes the window to the content's ideal size, which made it 860 by
        // 1838 points: taller than the screen, with pages floating mid-window.
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1060, height: 720))
        window.minSize = NSSize(width: 760, height: 520)
        window.delegate = self
        // A new autosave name, since 0.3.0–0.3.2 saved the oversized frame.
        if !window.setFrameUsingName("FindMyRingWindow") { window.center() }
        window.setFrameAutosaveName("FindMyRingWindow")
        Self.keepOnScreen(window)
        return window
    }

    /// Shrinks and moves a restored frame so all of it fits the screen.
    private static func keepOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: false)
    }
}

/// Dock icon on or off: off while only the menu bar is in use.
@MainActor
enum DockPolicy {
    static let alwaysKey = "alwaysShowInDock"

    static var alwaysInDock: Bool { UserDefaults.standard.bool(forKey: alwaysKey) }

    static func apply() {
        NSApp.setActivationPolicy(alwaysInDock ? .regular : .accessory)
    }

    static func windowOpened() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    static func windowClosed() {
        if !alwaysInDock { NSApp.setActivationPolicy(.accessory) }
    }
}

/// `beckon://` links, for Raycast, Alfred, Stream Deck and bookmarks:
///   beckon://ring/<name or id>   rings it
///   beckon://palette             opens the ring palette
///   beckon://airtags             opens Find My's Items tab
///   beckon://open                opens the window
@MainActor
enum LinkHandler {
    static func handle(_ url: URL) {
        // beckon:// since 0.4.1; findmyring:// links from before the rename still work.
        guard let scheme = url.scheme?.lowercased(), scheme == "beckon" || scheme == "findmyring" else { return }
        let model = AppModel.shared
        switch url.host?.lowercased() {
        case "ring":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = items.first { $0.name == "id" }?.value
            let name = items.first { $0.name == "name" }?.value ?? String(url.path.drop { $0 == "/" })
            // The id wins; the name is only a fallback (hand-typed links, or
            // a device whose id changed).
            if let target = id.flatMap(model.config.target(id:)) ?? model.target(named: name) {
                Task { await model.ringWithHUD(target, source: "Link") }
            } else {
                RingHUD.shared.show(.failed(name.isEmpty ? nil : name, "Beckon doesn't know that name."))
            }
        case "palette":
            RingPalette.shared.show()
        case "airtags":
            model.openAirTagsInFindMy()
        default:
            MainWindowController.shared.show()
        }
    }
}
