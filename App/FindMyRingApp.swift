import SwiftUI

@main
struct FindMyRingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
        DockPolicy.apply()
        let model = AppModel.shared
        Hotkeys.install()
        model.willAppear()
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
