import AppKit
import SwiftUI
import WidgetKit

/// `Beckon --screenshots <folder>`: draws every screen with made-up devices
/// (`DemoData`), saves each as a PNG with its window shadow, and quits. The
/// README and website images come from here, so they never show anyone's
/// real devices. Nothing rings, and the real settings, history and Keychain
/// are never read or written (`SharedStore.demo`).
///
/// The windows sit behind every other window so they don't cover what you're
/// doing; `screencapture -l` still captures them. Set BECKON_SHOTS_ONSCREEN=1
/// to bring them to the front instead.
@MainActor
enum Screenshots {
    static let folder: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()

    // An isolated, interactive sign-in form for UI verification. Never reads
    // saved accounts; use an invalid email to exercise validation without Apple.
    static var signInPreview: Bool { CommandLine.arguments.contains("--signin-preview") }
    static var active: Bool { folder != nil || signInPreview }

    static func run() async {
        if signInPreview {
            MainWindowController.shared.show()
            return
        }
        guard let folder else { return }
        NSApp.appearance = NSAppearance(named: .aqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel.shared
        let config = SharedStore.load()

        // The window, one page at a time.
        for (section, name) in [(WindowSection.all, "window-all"), (.favorites, "window-favorites"),
                                (.airTags, "window-airtags"), (.history, "window-history"),
                                (.settings, "window-settings")] {
            model.section = section
            await shoot(name, style: .window(NSSize(width: 980, height: 640))) {
                MainWindow().environmentObject(model)
            }
        }

        // The menu bar popover and the palette, as you type.
        await shoot("menu", style: .rounded) { MenuPopover().environmentObject(model) }
        for query in ["", "a", "ai", "air"] {
            await shoot("palette-\(query.isEmpty ? "empty" : query)", style: .rounded) {
                PaletteView(query: query, autofocus: false, close: {}).environmentObject(model)
            }
        }

        // The on-screen confirmation.
        let phone = config.favorites[0]
        let airPods = config.target(id: DemoData.airPodsID) ?? phone
        await shoot("hud-ringing", style: .clear) {
            HUDView(symbol: "speaker.wave.2.fill", title: "Ringing \(airPods.name)", detail: "Signing in to iCloud…", busy: true)
        }
        await shoot("hud-sent", style: .clear) {
            HUDView(symbol: "speaker.wave.2.fill", title: "Ringing \(airPods.name)", detail: "Sent · Apple will email you", busy: false)
        }

        // The widgets, plain and right after a tap.
        func favorites(_ state: RingState?, on target: RingTarget) -> FavoritesEntry {
            FavoritesEntry(date: .now, signedIn: true, favorites: config.favorites,
                           hotkeyText: config.hotkeyText, hotkeyTargetID: config.hotkeyRingTarget?.id,
                           status: state.map { .init(target: target.id, state: $0, date: .now) })
        }
        for (state, suffix) in [(RingState?.none, "ring"), (.ringing, "sending"), (.sent, "sent")] {
            await shoot("widget-small-\(suffix)", style: .clear) {
                WidgetFrame(family: .systemSmall) { FavoritesView(entry: favorites(state, on: phone), familyOverride: .systemSmall) }
            }
            await shoot("widget-medium-\(suffix)", style: .clear) {
                WidgetFrame(family: .systemMedium) { FavoritesView(entry: favorites(state, on: airPods), familyOverride: .systemMedium) }
            }
        }
        let history = SharedStore.history()
        func recent(_ events: [SharedStore.RingEvent]) -> RecentEntry {
            RecentEntry(date: .now, items: events.map { .init(id: $0.id, event: $0, target: config.target(id: $0.target)) })
        }
        await shoot("widget-recent", style: .clear) {
            WidgetFrame(family: .systemMedium) { RecentView(entry: recent(history), familyOverride: .systemMedium) }
        }
        let rang = SharedStore.RingEvent(target: airPods.id, name: airPods.name, kind: airPods.kind,
                                         date: .now, source: "Palette", ok: true, note: nil)
        await shoot("widget-recent-after", style: .clear) {
            WidgetFrame(family: .systemMedium) {
                RecentView(entry: recent([rang] + history.filter { $0.target != airPods.id }), familyOverride: .systemMedium)
            }
        }
        NSApp.terminate(nil)
    }

    enum Style: Equatable {
        /// A normal titled window of this size.
        case window(NSSize)
        /// Rounded corners and a shadow, sized to the view (the menu, the palette).
        case rounded
        /// No frame or background: the view draws its own (HUD, widgets).
        case clear
    }

    private static func shoot<V: View>(_ name: String, style: Style, @ViewBuilder _ content: () -> V) async {
        let panel: ShotPanel
        switch style {
        case .window(let size):
            let host = NSHostingController(rootView: content())
            panel = ShotPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                              backing: .buffered, defer: false)
            panel.title = "Beckon"
            panel.titlebarAppearsTransparent = true
            host.sizingOptions = []
            panel.contentViewController = host
            panel.setContentSize(size)
        case .rounded, .clear:
            // A title bar would add an empty band, so the rounded corners,
            // hairline and shadow are drawn here instead.
            let view = style == .clear ? AnyView(content()) : AnyView(
                content()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.1)))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .padding(36))
            let host = NSHostingController(rootView: view)
            panel = ShotPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentViewController = host
            panel.setContentSize(host.view.fittingSize)
        }
        panel.isReleasedWhenClosed = false
        // macOS won't capture a window placed off screen, but it does capture
        // one hidden behind others, so by default each sits just above the
        // wallpaper, under every app window.
        panel.level = ProcessInfo.processInfo.environment["BECKON_SHOTS_ONSCREEN"] == "1"
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.center()
        panel.orderFrontRegardless()
        if case .window = style { panel.makeKey() }   // active title bar and selection colors
        try? await Task.sleep(for: .milliseconds(900))

        let url = folder!.appendingPathComponent(name + ".png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-t", "png", "-l", String(panel.windowNumber), url.path]
        do {
            try capture.run()
            capture.waitUntilExit()
            print(FileManager.default.fileExists(atPath: url.path) ? "saved \(name)" : "FAILED \(name)")
        } catch {
            print("couldn't capture \(name): \(error)")
        }
        panel.orderOut(nil)
    }
}

/// A panel that can become key without activating the app.
private final class ShotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A desktop widget's size, margins, corners and shadow, for widget views
/// drawn by the app.
private struct WidgetFrame<Content: View>: View {
    let family: WidgetFamily
    @ViewBuilder let content: Content

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 164, height: 164)
        case .systemLarge: CGSize(width: 344, height: 354)
        default: CGSize(width: 344, height: 164)
        }
    }

    var body: some View {
        content
            .padding(14)
            .frame(width: size.width, height: size.height)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            .padding(28)
    }
}

/// The made-up account the screenshots show.
enum DemoData {
    static let phoneID = "demo-iphone"
    static let airPodsID = "demo-airpods"

    static var store: SharedStore.Demo {
        func device(_ id: String, _ name: String, _ model: String, _ cls: String, online: Bool = true) -> SharedStore.CachedDevice {
            SharedStore.CachedDevice(id: id, name: name, model: model, deviceClass: cls, online: online)
        }
        var config = SharedStore.Config()
        config.appleID = "alex@example.com"
        config.devices = [
            device(phoneID, "Alex's iPhone", "iPhone 17 Pro", "iPhone"),
            device("demo-ipad", "Alex's iPad", "iPad Air (M3)", "iPad"),
            device("demo-mac", "Alex's MacBook Air", "MacBook Air (M4)", "MacBook Air"),
            device(airPodsID, "Alex's AirPods Pro", "AirPods Pro 3", "Accessory"),
            device("demo-watch", "Alex's Apple Watch", "Apple Watch Series 11", "Watch"),
            device("demo-max", "Alex's AirPods Max", "AirPods Max", "Accessory"),
            device("demo-oldmac", "Old iMac", "iMac (24-inch, 2021)", "iMac", online: false),
        ]
        config.favoriteIDs = [phoneID, airPodsID, "demo-watch"]
        config.hiddenIDs = ["demo-oldmac"]
        config.airTags = ["Keys", "Backpack", "Wallet", "Car", "Suitcase"]
        config.favoriteAirTags = ["Keys"]
        config.lastRefresh = .now.addingTimeInterval(-3 * 3600)
        config.hotkeyTarget = phoneID
        config.hotkeyText = "⌃⌥⌘R"

        let now = Date.now
        func event(_ minutesAgo: Double, _ target: String, _ name: String, _ kind: DeviceKind, _ source: String, ok: Bool = true, note: String? = nil) -> SharedStore.RingEvent {
            SharedStore.RingEvent(target: target, name: name, kind: kind, date: now.addingTimeInterval(-minutesAgo * 60),
                                  source: source, ok: ok, note: note)
        }
        let history = [
            event(18, phoneID, "Alex's iPhone", .phone, "Widget"),
            event(95, RingTarget.airTagPrefix + "Keys", "Keys", .airTag, "Palette"),
            event(60 * 26, "demo-watch", "Alex's Apple Watch", .watch, "Shortcut key"),
            event(60 * 50, "demo-ipad", "Alex's iPad", .tablet, "Menu"),
        ]
        return SharedStore.Demo(config: config, history: history)
    }
}
