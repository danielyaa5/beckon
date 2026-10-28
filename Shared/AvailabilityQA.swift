#if BECKON_QA
import Foundation
import FindMyRingKit

/// Only compiled into the separate QA app and extension. These calls cannot
/// contact Apple or operate a real device.
enum AvailabilityQA {
    static var folder: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)!
    }
    static var configuration: SharedStore.Config {
        var config = SharedStore.Config()
        config.appleID = "qa@example.invalid"
        config.devices = [
            .init(id: "qa-phone", name: "Test iPhone", model: "iPhone", deviceClass: "iPhone", online: true),
            .init(id: "qa-offline", name: "Test Mac", model: "Mac", deviceClass: "Mac", online: false),
            .init(id: "qa-unknown", name: "Unknown device", model: "iPad", deviceClass: "iPad", online: nil),
        ]
        config.favoriteIDs = config.devices.map(\.id)
        return config
    }
    static func snapshot() -> AvailabilitySnapshot {
        let url = folder.appendingPathComponent("qa-state.txt")
        let state = (try? String(contentsOf: url, encoding: .utf8)).flatMap(DeviceAvailability.init(rawValue:)) ?? .online
        return AvailabilitySnapshot(devices: ["qa-phone": state, "qa-offline": .offline, "qa-unknown": .unknown], checkedAt: .now, valid: true)
    }
    static func set(_ state: DeviceAvailability) {
        try? state.rawValue.write(to: folder.appendingPathComponent("qa-state.txt"), atomically: true, encoding: .utf8)
    }
    static func receipt() {
        try? Date.now.ISO8601Format().write(to: folder.appendingPathComponent("qa-ring-receipt.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
