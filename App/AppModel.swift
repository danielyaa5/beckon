import AppKit
import FindMyRingKit
import WidgetKit
import os

/// Sections of the main window's sidebar.
enum WindowSection: Hashable {
    case all, favorites, group(String), hidden, history, settings
}

@MainActor
final class AppModel: ObservableObject {
    /// One model for the app's lifetime, made at launch: launch work (finding
    /// the sign-in, loading devices for the widgets, the shortcut keys) can't
    /// wait for the menu to be opened.
    static let shared = AppModel()

    @Published private(set) var config: SharedStore.Config
    @Published private(set) var history: [SharedStore.RingEvent] = []
    /// The latest outcome, shown at the bottom of the menu.
    @Published var status = ""
    @Published private(set) var refreshing = false
    /// The target being rung right now.
    @Published private(set) var ringingID: String?
    /// What the main window shows.
    @Published var section: WindowSection = .all

    private let service = FindMyService()
    /// The one automatic list load (when none is saved) was tried this launch.
    private var triedFirstLoad = false
    /// What a failed reload put on the status line, so the next good reload
    /// clears it (and nothing else).
    private var refreshError: String?
    private static let log = Logger(subsystem: "com.danielyakobian.findmy-ring", category: "app")

    private init() {
        SharedStore.prepare()
        config = SharedStore.load()
        history = SharedStore.history()
        // Re-save in the current format: since 0.4 the device list keeps no
        // battery, location or place, so this drops any an older version saved.
        if !config.devices.isEmpty { SharedStore.save(config) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Reading

    /// Beckon doesn't ring AirTags (Apple's web Find My can't), so the AirTag
    /// entries in the menu and window open Find My's Items tab instead.
    func openAirTagsInFindMy() {
        if !NSWorkspace.shared.open(URL(string: "findmy://items")!) {
            status = "Couldn't open Find My. Open it from Applications and choose Items."
        }
    }

    var appleID: String { config.appleID ?? "" }
    var hasCredentials: Bool { !appleID.isEmpty && SharedStore.password(appleID: appleID) != nil }
    var favorites: [RingTarget] { config.favorites }
    var hotkeyTarget: RingTarget? { config.hotkeyRingTarget }

    var listLoadedText: String {
        config.lastRefresh.map { "Device list loaded " + $0.formatted(date: .abbreviated, time: .shortened) }
            ?? "Device list not loaded yet"
    }

    /// What a target is ("iPhone 18 Pro"): the app keeps no
    /// battery, location or place to show.
    func detail(_ t: RingTarget) -> String { Describe.detail(t) }
    func isFavorite(_ t: RingTarget) -> Bool { config.isFavorite(t) }
    func isHidden(_ t: RingTarget) -> Bool { config.isHidden(t) }

    /// Name or model matches; favorites first, hidden devices last, and
    /// offline devices after online ones.
    func search(_ query: String) -> [RingTarget] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = config.allTargets
        let matches = q.isEmpty ? all : all.filter {
            $0.name.lowercased().contains(q)
                || $0.device.model.lowercased().contains(q)
        }
        return matches.enumerated().sorted { a, b in
            let ka = (isFavorite(a.element) ? 0 : 1, isHidden(a.element) ? 1 : 0,
                      a.element.device.online == false ? 1 : 0, a.offset)
            let kb = (isFavorite(b.element) ? 0 : 1, isHidden(b.element) ? 1 : 0,
                      b.element.device.online == false ? 1 : 0, b.offset)
            return ka < kb
        }.map(\.element)
    }

    func targets(in section: WindowSection) -> [RingTarget] {
        switch section {
        case .all: Self.onlineFirst(config.visibleDevices).map(RingTarget.device)
        case .favorites: favorites
        case .group(let g): Self.onlineFirst(config.visibleDevices.filter { $0.kind.group == g }).map(RingTarget.device)
        case .hidden: config.devices.filter { config.hiddenIDs.contains($0.id) }.map(RingTarget.device)
        case .history, .settings: []
        }
    }

    /// Online devices before offline ones (often long-gone Macs), each group
    /// in Apple's order, as in the menu and palette.
    private static func onlineFirst(_ devices: [SharedStore.CachedDevice]) -> [SharedStore.CachedDevice] {
        devices.filter { $0.online != false } + devices.filter { $0.online == false }
    }

    /// Sidebar groups that have devices, in a fixed order.
    var groups: [String] {
        let present = Set(config.visibleDevices.map(\.kind.group))
        return ["iPhone and iPad", "Mac", "Audio", "Watch", "Other"].filter(present.contains)
    }

    // MARK: Changing

    private func commit(_ change: (inout SharedStore.Config) -> Void) {
        change(&config)
        SharedStore.save(config)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func toggleFavorite(_ t: RingTarget) {
        commit { c in
            var favs = Set(c.favoriteIDs)
            if favs.contains(t.id) { favs.remove(t.id) } else { favs.insert(t.id) }
            c.favoriteIDs = c.devices.map(\.id).filter(favs.contains)
        }
    }

    func setHidden(_ t: RingTarget, _ hidden: Bool) {
        commit { c in
            c.hiddenIDs.removeAll { $0 == t.id }
            if hidden { c.hiddenIDs.append(t.id) }
        }
    }

    func setHotkeyTarget(_ t: RingTarget?) { commit { $0.hotkeyTarget = t?.id } }

    func setHotkeyText(_ text: String?) {
        guard config.hotkeyText != text else { return }
        commit { $0.hotkeyText = text }
    }

    func reloadHistory() { history = SharedStore.history() }

    func clearHistory() {
        SharedStore.clearHistory()
        reloadHistory()
        WidgetCenter.shared.reloadTimelines(ofKind: "RecentWidget")
    }

    // MARK: Account

    /// Signs in with Apple first and saves the password only once Apple has
    /// accepted it, so a mistyped password never shows as "Signed in" and is
    /// never retried in the background.
    func signIn(appleID raw: String, password: String) async -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, !password.isEmpty, !refreshing else { return false }
        guard id.contains("@"), id.contains(".") else {
            status = "Enter the email address of your Apple Account."
            return false
        }
        refreshing = true
        defer { refreshing = false }
        status = "Signing in…"
        await service.forget()
        do {
            let found = try await service.devices(appleID: id, password: password)
            try SharedStore.savePassword(password, appleID: id)
            let devices = Self.cachedDevices(found)
            commit {
                $0.appleID = id
                $0.devices = devices
                $0.lastRefresh = .now
            }
            // The list was already fetched during sign-in, even if it is empty.
            // Opening the signed-in view must not immediately fetch it again.
            triedFirstLoad = true
            refreshError = nil
            status = devices.isEmpty ? "No ringable devices found." : ""
            FindMyRingShortcuts.updateAppShortcutParameters()
            return true
        } catch let error as RingError {
            status = error.message
        } catch {
            status = "Couldn't sign in: \(error.localizedDescription)"
        }
        await service.forget()
        return false
    }

    /// Apple turned the saved password down: it was changed, or the account is
    /// locked. Forget it, so nothing signs in with it again in the background
    /// (repeated rejected sign-ins are what get an Apple Account locked), and
    /// let the menu ask for it again. Devices and favorites stay.
    private func rejectSavedPassword(_ error: RingError) {
        SharedStore.forgetPassword(appleID: appleID)
        Task { await service.forget() }
        WidgetCenter.shared.reloadAllTimelines()
        status = error.kind == .accountLocked
            ? error.message
            : "Apple didn't accept the saved password. Sign in again."
        Self.log.error("Apple rejected the saved password; forgot it")
    }

    func signOut() {
        SharedStore.clear(appleID: appleID)
        Task { await service.forget() }
        config = SharedStore.load()
        WidgetCenter.shared.reloadAllTimelines()
        status = "Signed out."
    }

    // MARK: Loading devices

    func refresh() async {
        guard !refreshing else { return }
        guard let password = SharedStore.password(appleID: appleID) else {
            status = "Sign in first."
            return
        }
        refreshing = true
        defer { refreshing = false }
        do {
            let found = try await service.devices(appleID: appleID, password: password)
            let devices = Self.cachedDevices(found)
            // An empty or unreadable reply must not wipe a list that worked:
            // the menu and widgets would go blank until the next reload.
            if devices.isEmpty, !config.devices.isEmpty {
                Self.log.error("Reload returned no ringable devices; kept the \(self.config.devices.count, privacy: .public) saved ones")
                showRefreshError("Apple returned no devices this time, so the last list is kept.")
                return
            }
            commit {
                $0.devices = devices
                $0.lastRefresh = .now
            }
            Self.log.notice("Loaded the device list: \(devices.count, privacy: .public) devices")
            if devices.isEmpty { status = "No ringable devices found." }
            else if let e = refreshError, status == e { status = "" }
            else if status.hasPrefix("Sign") || status.hasPrefix("Couldn't load") { status = "" }
            refreshError = nil
            FindMyRingShortcuts.updateAppShortcutParameters()
        } catch let error as RingError {
            showRefreshError(error.message)
            if error.kind == .badCredentials || error.kind == .accountLocked { rejectSavedPassword(error) }
        } catch {
            showRefreshError("Couldn't load devices: \(error.localizedDescription)")
        }
    }

    private static func cachedDevices(_ found: [FoundDevice]) -> [SharedStore.CachedDevice] {
        // Keep only the fields ringing needs, never location or battery data.
        found.filter(\.canRing).map {
            SharedStore.CachedDevice(id: $0.id, name: $0.name, model: $0.model,
                                     deviceClass: $0.deviceClass, online: $0.isOnline)
        }
    }

    private func showRefreshError(_ message: String) {
        status = message
        refreshError = message
    }

    /// When the menu, palette or window opens. Nothing is reloaded from
    /// Apple here: the list loads at sign-in or on Reload, so the app signs in
    /// only to ring. The one exception is a first load when no list is saved.
    func willAppear() {
        reloadHistory()
        guard hasCredentials, !refreshing, config.devices.isEmpty, !triedFirstLoad else { return }
        triedFirstLoad = true
        Task { await refresh() }
    }

    // MARK: Ringing

    /// Rings one device through iCloud and records it.
    @discardableResult
    func ring(_ t: RingTarget, source: String) async -> Bool {
        guard ringingID == nil else {
            status = "Still ringing the last one…"
            return false
        }
        ringingID = t.id
        defer { ringingID = nil }
        status = "Ringing \(t.name)…"

        var problem: String?
        if let password = SharedStore.password(appleID: appleID) {
            do {
                try await service.ring(deviceID: t.device.id, appleID: appleID, password: password)
            } catch let error as RingError {
                problem = error.message
                if error.kind == .badCredentials || error.kind == .accountLocked { rejectSavedPassword(error) }
            } catch {
                problem = error.localizedDescription
            }
        } else {
            problem = "Sign in first."
        }

        let ok = problem == nil
        status = problem ?? "Rang \(t.name). Apple will email you."
        SharedStore.record(.init(
            target: t.id, name: t.name, kind: t.kind, date: .now, source: source, ok: ok, note: problem))
        reloadHistory()
        WidgetCenter.shared.reloadTimelines(ofKind: "RecentWidget")
        Self.log.notice("Ring from \(source, privacy: .public): \(ok ? "sent" : "failed", privacy: .public)")
        return ok
    }

    /// Rings with the on-screen confirmation: for the shortcut key, the
    /// palette, links and Shortcuts, where the menu isn't open.
    func ringWithHUD(_ t: RingTarget, source: String) async {
        RingHUD.shared.show(.ringing(t))
        let ok = await ring(t, source: source)
        RingHUD.shared.show(ok ? .sent(t) : .failed(t.name, status))
    }

    func ringHotkeyTarget() async {
        guard let t = hotkeyTarget else {
            RingHUD.shared.show(.failed(nil, "Star a device in Beckon first."))
            return
        }
        await ringWithHUD(t, source: "Shortcut key")
    }

    /// For links and Shortcuts: an id, or a name (exact, then case-insensitive).
    func target(named name: String) -> RingTarget? {
        let all = config.allTargets
        return config.target(id: name)
            ?? all.first { $0.name == name }
            ?? all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? all.first { Self.loose($0.name) == Self.loose(name) }
    }

    /// A name with case, curly apostrophes, punctuation and extra spaces
    /// ignored: Siri and typed links rarely match "Daniel’s iPhone" exactly.
    private static func loose(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let kept = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ").joined(separator: " ")
    }
}
