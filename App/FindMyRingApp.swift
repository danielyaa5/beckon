import SwiftUI

@main
struct FindMyRingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.key) private var showMenuBarIcon = true

    /// Settings can hide the icon; screenshots and the status probe never show
    /// it, and never save their hidden icon as the setting.
    private var menuBarIconInserted: Binding<Bool> {
        Binding(get: { showMenuBarIcon && !Screenshots.active && !StatusProbe.active },
                set: { if !Screenshots.active && !StatusProbe.active { showMenuBarIcon = $0 } })
    }

    init() {
        // Before anything reads the settings: screenshots use made-up devices.
        if Screenshots.active {
            SharedStore.demo = (Screenshots.signInPreview || Screenshots.walkthroughPreview)
                ? SharedStore.Demo(config: SharedStore.Config(), history: []) : DemoData.store
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconInserted) {
            MenuPopover().environmentObject(AppModel.shared)
        } label: {
            Image(systemName: "iphone.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { MainWindowController.shared.show(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Launch work that can't wait for the menu to be opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything can show a dialog and replace the launch event.
        let launchedByPerson = MenuBarIcon.launchedByPerson
        if StatusProbe.active {
            NSApp.setActivationPolicy(.accessory)
            Task { await StatusProbe.run() }
            return
        }
        if Screenshots.active {
            NSApp.setActivationPolicy(.accessory)
            Task { await Screenshots.run() }
            return
        }
        #if BECKON_QA
        AppModel.shared.startMonitoring()
        MainWindowController.shared.show()
        AvailabilityQAController.show()
        return
        #endif
        guard Installation.finishIfInstalled() else {
            NSApp.terminate(nil)
            return
        }
        AppUpdater.shared.start()
        DockPolicy.apply()
        let model = AppModel.shared
        Hotkeys.install()
        model.willAppear()
        let backgroundLaunch = CommandLine.arguments.contains("--background")
        if !backgroundLaunch && OnboardingController.shouldShow(hasCredentials: model.hasCredentials) {
            OnboardingController.shared.show()
        } else if !backgroundLaunch && !model.hasCredentials {
            MainWindowController.shared.show()
        } else if !backgroundLaunch && !MenuBarIcon.isShown && launchedByPerson {
            // With no menu bar icon, opening the app has to show something.
            MainWindowController.shared.show()
        }
        if !backgroundLaunch { Task { await Installation.offerCleanup() } }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(LinkHandler.handle)
    }

    /// Opening the app again (Finder, Spotlight, the Dock) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if OnboardingController.shared.isVisible {
            OnboardingController.shared.show()
        } else {
            MainWindowController.shared.show()
        }
        return true
    }
}
