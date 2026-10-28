import AppIntents
import WidgetKit
import os
import FindMyRingKit

/// Rings one device. Runs in the widget extension process (openAppWhenRun =
/// false), reading the password from the shared Keychain group, so a widget tap
/// works with the app closed.
///
/// macOS doesn't redraw a widget while its button's intent is still running
/// (chronod logs "Reload not permitted"), and signing in plus the ring take
/// 2–3 seconds. So `perform()` only marks the button "Sending…" and returns
/// at once, which lets the widget show it, and the ring itself finishes in a
/// task that marks it "Sent" or "Didn't ring" when Apple answers.
struct RingDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ring a device"
    static let description = IntentDescription("Play a sound on one of your Apple devices.")
    static let openAppWhenRun = false

    @Parameter(title: "Device ID") var deviceID: String
    @Parameter(title: "Device Name") var deviceName: String

    init() {}
    init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let config = SharedStore.load()
        let kind = config.devices.first { $0.id == deviceID }?.kind ?? .other
        let ring = WidgetRing(deviceID: deviceID, deviceName: deviceName, kind: kind)
        guard let appleID = config.appleID,
              let password = SharedStore.password(appleID: appleID)
        else {
            SharedStore.log.error("Widget ring: no saved sign-in")
            ring.finish(ok: false, note: "Not signed in")
            throw RingError(.badCredentials, "Open Beckon and sign in first.")
        }
        ring.setStatus(.ringing)
        SharedStore.log.notice("Widget ring: sending")
        Task.detached { await ring.send(appleID: appleID, password: password) }
        return .result()
    }
}

/// One ring from the widget, finished after the button's intent has returned.
struct WidgetRing: Sendable {
    let deviceID: String
    let deviceName: String
    let kind: DeviceKind

    func send(appleID: String, password: String) async {
        // Keep the extension from being idled out mid-ring.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Ringing a device")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            #if BECKON_QA
            let snapshot = AvailabilityQA.snapshot()
            #else
            let client = FindMyRing(appleID: appleID)
            try await client.signIn(password: password)
            let snapshot = try await client.availability()
            #endif
            SharedStore.saveAvailability(snapshot)
            guard snapshot.state(for: deviceID) == .online else {
                finish(ok: false, note: snapshot.state(for: deviceID) == .offline
                       ? "Offline. Open Find My to request a sound when it reconnects." : "Needs refresh.", state: .needsRefresh)
                return
            }
            #if BECKON_QA
            AvailabilityQA.receipt()
            #else
            try await client.playSound(deviceID: deviceID, subject: "Beckon")
            #endif
            SharedStore.log.notice("Widget ring sent")
            finish(ok: true, note: nil)
        } catch {
            SharedStore.log.error("Widget ring failed: \(String(describing: error), privacy: .public)")
            let state: SharedStore.WidgetRingStatus.State = (error as? RingError)?.kind == .uncertain ? .uncertain : .failed
            finish(ok: false, note: String(describing: error), state: state)
        }
    }

    func setStatus(_ state: SharedStore.WidgetRingStatus.State) {
        SharedStore.setWidgetRingStatus(.init(target: deviceID, state: state, date: .now))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func finish(ok: Bool, note: String?, state: SharedStore.WidgetRingStatus.State? = nil) {
        SharedStore.record(.init(target: deviceID, name: deviceName, kind: kind, date: .now,
                                 source: "Widget", ok: ok, note: note, uncertain: state == .uncertain))
        setStatus(state ?? (ok ? .sent : .failed))
    }
}

/// Always available, even when the last rendered Ring button is disabled.
struct RefreshDeviceStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh device status"
    static let openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        let config = SharedStore.load()
        guard let account = config.appleID, let password = SharedStore.password(appleID: account) else { return .result() }
        do {
            #if BECKON_QA
            let snapshot = AvailabilityQA.snapshot()
            #else
            let client = FindMyRing(appleID: account)
            try await client.signIn(password: password)
            let snapshot = try await client.availability()
            #endif
            SharedStore.saveAvailability(snapshot)
        } catch {
            SharedStore.saveAvailability(AvailabilitySnapshot(checkedAt: .now))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
