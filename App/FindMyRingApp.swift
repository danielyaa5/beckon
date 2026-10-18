import SwiftUI

@main
struct FindMyRingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before anything reads the settings: screenshots use made-up devices.
        if Screenshots.active {
            SharedStore.demo = Screenshots.signInPreview
                ? SharedStore.Demo(config: SharedStore.Config(), history: []) : DemoData.store
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!Screenshots.active)) {
            MenuPopover().environmentObject(AppModel.shared)
        } label: {
            Image(systemName: "iphone.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Launch work that can't wait for the menu to be opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Screenshots.active {
            NSApp.setActivationPolicy(.accessory)
            Task { await Screenshots.run() }
            return
        }
        guard Installation.finishIfInstalled() else {
            NSApp.terminate(nil)
            return
        }
        AppUpdater.shared.start()
        DockPolicy.apply()
        let model = AppModel.shared
        Hotkeys.install()
        model.willAppear()
        if !model.hasCredentials { MainWindowController.shared.show() }
        Task { await Installation.offerCleanup() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(LinkHandler.handle)
    }

    /// Opening the app again (Finder, Spotlight, the Dock) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}
