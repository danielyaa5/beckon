import AppIntents

/// A device, as Shortcuts, Spotlight and Siri see it.
struct DeviceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")
    static let defaultQuery = DeviceQuery()

    let id: String
    let name: String
    let detail: String
    let symbol: String

    init(_ t: RingTarget) {
        id = t.id
        name = t.name
        detail = t.device.model
        symbol = t.kind.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)", image: .init(systemName: symbol))
    }
}

struct DeviceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [DeviceEntity] {
        let all = SharedStore.load().allTargets
        return identifiers.compactMap { id in all.first { $0.id == id }.map(DeviceEntity.init) }
    }

    func entities(matching string: String) async throws -> [DeviceEntity] {
        SharedStore.load().allTargets
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(DeviceEntity.init)
    }

    /// Favorites first, hidden devices left out.
    func suggestedEntities() async throws -> [DeviceEntity] {
        let config = SharedStore.load()
        let favorites = config.favorites
        let rest = config.allTargets.filter { t in !favorites.contains(t) && !config.isHidden(t) }
        return (favorites + rest).map(DeviceEntity.init)
    }
}

/// "Ring a Device": runs in the app, which shows the on-screen confirmation.
struct RingDeviceShortcut: AppIntent {
    static let title: LocalizedStringResource = "Ring a Device"
    static let description = IntentDescription("Plays a sound on one of your Apple devices.")

    @Parameter(title: "Device")
    var device: DeviceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Ring \(\.$device)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.config.target(id: device.id) ?? model.target(named: device.name) else {
            return .result(dialog: "Beckon doesn't know \(device.name) any more. Reload its devices and try again.")
        }
        await model.ringWithHUD(target, source: "Shortcuts")
        return .result(dialog: "\(model.status)")
    }
}

struct FindMyRingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RingDeviceShortcut(),
            phrases: [
                "Ring \(\.$device) with \(.applicationName)",
                "Find \(\.$device) with \(.applicationName)",
                "Ring my device with \(.applicationName)",
            ],
            shortTitle: "Ring a Device",
            systemImageName: "speaker.wave.2.fill"
        )
    }
}
