import SwiftUI
import Sparkle
import Combine

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    @Published var automaticallyChecks = false {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    private var observation: AnyCancellable?

    private init() {
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    func start() {
        controller.startUpdater()
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Button("Check for Updates…", action: updater.check)
            .disabled(!updater.canCheck)
    }
}

struct UpdateSettings: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
        CheckForUpdatesButton()
    }
}
