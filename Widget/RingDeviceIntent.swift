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
            let client = FindMyRing(appleID: appleID)
            try await client.signIn(password: password)
            try await client.playSound(deviceID: deviceID, subject: "Beckon")
            SharedStore.log.notice("Widget ring sent")
            finish(ok: true, note: nil)
        } catch {
            SharedStore.log.error("Widget ring failed: \(String(describing: error), privacy: .public)")
            finish(ok: false, note: String(describing: error))
        }
    }

    func setStatus(_ state: SharedStore.WidgetRingStatus.State) {
        SharedStore.setWidgetRingStatus(.init(target: deviceID, state: state, date: .now))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func finish(ok: Bool, note: String?) {
        SharedStore.record(.init(target: deviceID, name: deviceName, kind: kind, date: .now,
                                 source: "Widget", ok: ok, note: note))
        setStatus(ok ? .sent : .failed)
    }
}
