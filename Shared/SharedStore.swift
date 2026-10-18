import Foundation
import os
import FindMyRingKit

/// Storage shared between the app and the widget extension:
///   * Apple Account email, device list, favorites, hidden devices, AirTag
///     names → `config.json` in the App Group container
///   * the last 200 rings → `history.json` beside it (the widget adds to it too)
///   * password → data protection keychain, in a shared access group
/// so the widget can ring on its own. A sign-in itself keeps nothing.
///
/// On macOS the App Group is the team-prefixed kind (`<TeamID>.…`), not
/// `group.…`. Since macOS 15 the system only lets an app into a `group.`
/// container when its provisioning profile lists that group, and the
/// Developer ID profiles here don't, so up to 0.2.1 every read and write of
/// the container was denied (TCC "AppDataDetailed", no prompt): the app lost
/// its sign-in on relaunch and the widget never saw one. A team-prefixed
/// group needs no profile entry. iOS only accepts `group.` IDs.
enum SharedStore {
    #if os(macOS)
    static let appGroup = "4JWVY7832S.com.danielyakobian.findmy-ring"
    #else
    static let appGroup = "group.com.danielyakobian.findmy-ring"
    #endif
    /// Team-id prefix + group name; both app and widget hold this keychain group.
    static let keychainGroup = "4JWVY7832S.com.danielyakobian.findmy-ring"

    static let log = Logger(subsystem: "com.danielyakobian.findmy-ring", category: "store")

    /// Made-up devices and rings for screenshots (`Beckon --screenshots`).
    /// While set, nothing is read from or written to the real files or the
    /// Keychain: changes stay in memory and vanish when the app quits.
    struct Demo {
        var config: Config
        var history: [RingEvent]
    }
    nonisolated(unsafe) static var demo: Demo?

    /// One device, as much as ringing needs. Since 0.4 no battery, location
    /// or place is kept (the app doesn't collect device data); `online` sorts
    /// offline devices last and labels their availability at the last reload.
    struct CachedDevice: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let model: String
        var deviceClass: String?
        var online: Bool?

        var kind: DeviceKind { DeviceKind(model: model, deviceClass: deviceClass ?? "") }
    }

    struct Config: Codable {
        var appleID: String?
        var devices: [CachedDevice] = []
        /// Starred devices, in list order: the top of the menu and the widgets.
        var favoriteIDs: [String] = []
        /// Devices left out of the menu and widgets (old Macs and the like).
        var hiddenIDs: [String] = []
        /// AirTag names exactly as Find My shows them. Only the app can ring
        /// these (by driving the Find My app); widgets open the app to do it.
        var airTags: [String] = []
        var favoriteAirTags: [String] = []
        var lastRefresh: Date?
        /// What the global ring shortcut rings (a `RingTarget` id); nil means
        /// the first favorite.
        var hotkeyTarget: String?
        /// That shortcut as text ("⌃⌥⌘R"), for the widgets.
        var hotkeyText: String?

        init() {}

        /// Every key optional, so a file from an older version still loads.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appleID = try c.decodeIfPresent(String.self, forKey: .appleID)
            devices = try c.decodeIfPresent([CachedDevice].self, forKey: .devices) ?? []
            favoriteIDs = try c.decodeIfPresent([String].self, forKey: .favoriteIDs) ?? []
            hiddenIDs = try c.decodeIfPresent([String].self, forKey: .hiddenIDs) ?? []
            airTags = try c.decodeIfPresent([String].self, forKey: .airTags) ?? []
            favoriteAirTags = try c.decodeIfPresent([String].self, forKey: .favoriteAirTags) ?? []
            lastRefresh = try c.decodeIfPresent(Date.self, forKey: .lastRefresh)
            hotkeyTarget = try c.decodeIfPresent(String.self, forKey: .hotkeyTarget)
            hotkeyText = try c.decodeIfPresent(String.self, forKey: .hotkeyText)
        }

        /// Starred devices (list order), then starred AirTags.
        var favorites: [RingTarget] {
            let favs = Set(favoriteIDs), hidden = Set(hiddenIDs)
            return devices.filter { favs.contains($0.id) && !hidden.contains($0.id) }.map(RingTarget.device)
                + favoriteAirTags.map(RingTarget.airTag)
        }

        var visibleDevices: [CachedDevice] {
            let hidden = Set(hiddenIDs)
            return devices.filter { !hidden.contains($0.id) }
        }

        /// Everything that can be rung, hidden devices last.
        var allTargets: [RingTarget] {
            let hidden = Set(hiddenIDs)
            return visibleDevices.map(RingTarget.device)
                + airTags.map(RingTarget.airTag)
                + devices.filter { hidden.contains($0.id) }.map(RingTarget.device)
        }

        func target(id: String) -> RingTarget? {
            if id.hasPrefix(RingTarget.airTagPrefix) {
                let name = String(id.dropFirst(RingTarget.airTagPrefix.count))
                return airTags.contains(name) ? .airTag(name) : nil
            }
            return devices.first { $0.id == id }.map(RingTarget.device)
        }

        /// What the global shortcut rings.
        var hotkeyRingTarget: RingTarget? {
            hotkeyTarget.flatMap(target(id:)) ?? favorites.first
        }

        func isFavorite(_ t: RingTarget) -> Bool {
            t.isAirTag ? favoriteAirTags.contains(t.name) : favoriteIDs.contains(t.id)
        }

        func isHidden(_ t: RingTarget) -> Bool { !t.isAirTag && hiddenIDs.contains(t.id) }
    }

    // MARK: Files

    private static var folder: URL? {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            log.error("No App Group container for \(appGroup, privacy: .public)")
            return nil
        }
        return folder
    }

    private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = folder?.appendingPathComponent(name),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            log.error("Couldn't read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let url = folder?.appendingPathComponent(name) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func load() -> Config {
        if let demo { return demo.config }
        return read(Config.self, "config.json") ?? Config()
    }

    static func save(_ config: Config) {
        if demo != nil { demo?.config = config; return }
        write(config, "config.json")
    }

    static func update(_ change: (inout Config) -> Void) {
        var config = load()
        change(&config)
        save(config)
    }

    static var appleID: String? {
        get { load().appleID }
        set { update { $0.appleID = newValue } }
    }

    // MARK: Ring history

    struct RingEvent: Codable, Identifiable, Hashable, Sendable {
        var id = UUID()
        /// A `RingTarget` id.
        let target: String
        let name: String
        let kind: DeviceKind
        let date: Date
        /// "Menu", "Palette", "Shortcut key", "Widget", "Shortcuts", "Link".
        let source: String
        let ok: Bool
        let note: String?
    }

    static func history() -> [RingEvent] {
        if let demo { return demo.history }
        return read([RingEvent].self, "history.json") ?? []
    }

    /// The app and the widget both add rings, from separate processes; a file
    /// coordinator keeps one from overwriting the other's new entry.
    static func record(_ event: RingEvent) {
        if demo != nil { demo?.history.insert(event, at: 0); return }
        coordinatedWrite("history.json") {
            var events = history()
            events.insert(event, at: 0)
            write(Array(events.prefix(200)), "history.json")
        }
    }

    static func clearHistory() {
        if demo != nil { demo?.history = []; return }
        coordinatedWrite("history.json") { write([RingEvent](), "history.json") }
    }

    private static func coordinatedWrite(_ name: String, _ change: () -> Void) {
        guard let url = folder?.appendingPathComponent(name) else { return }
        var failure: NSError?
        var ran = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &failure) { _ in
            change()
            ran = true
        }
        if !ran {
            log.error("Couldn't coordinate \(name, privacy: .public): \(failure?.localizedDescription ?? "unknown", privacy: .public)")
            change()
        }
    }

    // MARK: Widget ring status

    /// What the widget's ring button shows after a tap: "Sending…" while
    /// the ring is on its way, then "Sent" or "Didn't ring" for a few
    /// seconds. Written only by the widget's intent, in its own file so the
    /// app's settings writes never race it.
    struct WidgetRingStatus: Codable, Hashable, Sendable {
        enum State: String, Codable, Sendable { case ringing, sent, failed }
        let target: String
        let state: State
        let date: Date

        /// When the button goes back to plain "Ring". A "ringing" that never
        /// finished (the extension was stopped) also times out.
        var expires: Date {
            switch state {
            case .ringing: date.addingTimeInterval(60)
            case .sent: date.addingTimeInterval(10)
            case .failed: date.addingTimeInterval(30)
            }
        }
    }

    static func widgetRingStatus(at now: Date = .now) -> WidgetRingStatus? {
        if demo != nil { return nil }
        guard let status = read(WidgetRingStatus.self, "widget-status.json"), status.expires > now else { return nil }
        return status
    }

    static func setWidgetRingStatus(_ status: WidgetRingStatus) {
        if demo != nil { return }
        write(status, "widget-status.json")
    }

    // MARK: Password

    static func savePassword(_ password: String, appleID: String) throws {
        if demo != nil { return }
        try KeychainStore.save(password: password, account: appleID, accessGroup: keychainGroup)
    }

    static func password(appleID: String) -> String? {
        guard !appleID.isEmpty else { return nil }
        if demo != nil { return "demo" }
        return KeychainStore.read(account: appleID, accessGroup: keychainGroup)
    }

    /// Only the password: devices, favorites and history stay for the next sign-in.
    static func forgetPassword(appleID: String) {
        if demo != nil { return }
        KeychainStore.delete(account: appleID, accessGroup: keychainGroup)
    }

    static func clear(appleID: String) {
        if demo != nil { return }
        KeychainStore.delete(account: appleID, accessGroup: keychainGroup)
        update { $0.devices = [] }
    }

    /// Run by the app at launch; the widget only reads. When the settings
    /// file names no Apple Account, takes it from the saved password itself
    /// (its account is the email), so a lost or never-written settings file
    /// doesn't sign you out.
    static func prepare() {
        if demo != nil { return }
        var config = load()
        if config.appleID?.isEmpty ?? true,
           let account = KeychainStore.savedAccount(accessGroup: keychainGroup) {
            config.appleID = account
            save(config)
        }
        let signedIn = password(appleID: config.appleID ?? "") != nil
        log.notice("App launch: signed in \(signedIn, privacy: .public), \(config.devices.count, privacy: .public) devices cached")
    }
}
