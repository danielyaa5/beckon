import AppKit
import FindMyRingKit

/// Bounded, read-only diagnostics. No names, account identifiers, credentials,
/// device IDs or raw Apple responses are written to the report.
@MainActor
enum StatusProbe {
    static var active: Bool { CommandLine.arguments.contains("--status-probe") }
    static func run() async {
        let report = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Beckon-status-probe.json")
        var samples: [[String: Any]] = []
        let config = SharedStore.load()
        // Export through Beckon's own App Group access, never by changing
        // filesystem permissions or copying Keychain material.
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: .now)
        let backup = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Beckon/Backups/availability-" + stamp)
        do {
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            for (name, data) in [("config.json", try encoder.encode(config)), ("history.json", try encoder.encode(SharedStore.history()))] {
                let destination = backup.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path) { try data.write(to: destination, options: .atomic) }
            }
        } catch { samples.append(["backup": "failed"]) }
        if let account = config.appleID, let password = SharedStore.password(appleID: account) {
            let service = FindMyService()
            for index in 0..<8 {
                let started = Date()
                do {
                    let snapshot = try await service.availability(appleID: account, password: password)
                    samples.append(["sample": index, "duration": Date().timeIntervalSince(started),
                                    "online": snapshot.devices.values.filter { $0 == .online }.count,
                                    "offline": snapshot.devices.values.filter { $0 == .offline }.count,
                                    "unknown": snapshot.devices.values.filter { $0 == .unknown }.count])
                } catch {
                    samples.append(["sample": index, "errorKind": (error as? RingError).map { String(describing: $0.kind) } ?? "other"])
                    break
                }
                if index < 7 { try? await Task.sleep(for: .seconds(1)) }
            }
        } else { samples.append(["blocked": "No saved sign-in in this account"]) }
        if let data = try? JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: report, options: .atomic)
        }
        NSApp.terminate(nil)
    }
    private static var runtimeSamples: [[String: Any]] = []
    static func recordRuntime(_ snapshot: AvailabilitySnapshot) {
        guard CommandLine.arguments.contains("--availability-diagnostics"), runtimeSamples.count < 10 else { return }
        runtimeSamples.append(["checkedAt": snapshot.checkedAt.timeIntervalSince1970,
                               "online": snapshot.devices.values.filter { $0 == .online }.count,
                               "offline": snapshot.devices.values.filter { $0 == .offline }.count,
                               "unknown": snapshot.devices.values.filter { $0 == .unknown }.count])
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Beckon-availability-runtime.json")
        if let data = try? JSONSerialization.data(withJSONObject: runtimeSamples, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: path, options: .atomic)
        }
    }

}
