import Foundation

/// Availability reported by Apple, not a direct reachability test.
public enum DeviceAvailability: String, Codable, Sendable {
    case online, offline, unknown

    public init(status: String?) {
        switch status {
        case "200": self = .online
        case "203": self = .offline
        default: self = .unknown
        }
    }

    public var title: String {
        switch self {
        case .online: "Reported online"
        case .offline: "Offline"
        case .unknown: "Needs refresh"
        }
    }
}

public struct AvailabilitySnapshot: Codable, Equatable, Sendable {
    public var devices: [String: DeviceAvailability]
    public var checkedAt: Date
    public var valid: Bool
    public static let maximumAge: TimeInterval = 15

    public init(devices: [String: DeviceAvailability] = [:], checkedAt: Date = .distantPast, valid: Bool = false) {
        self.devices = devices; self.checkedAt = checkedAt; self.valid = valid
    }

    public var expires: Date { checkedAt.addingTimeInterval(Self.maximumAge) }
    public func state(for id: String, at now: Date = .now) -> DeviceAvailability {
        guard valid, now >= checkedAt.addingTimeInterval(-5), now < expires else { return .unknown }
        return devices[id] ?? .unknown
    }
}

/// Polling targets one second without overlapping requests; errors reduce traffic.
public struct AvailabilityPollPolicy: Sendable {
    public private(set) var failures = 0
    public init() {}
    public mutating func completed(ok: Bool) -> TimeInterval {
        failures = ok ? 0 : min(failures + 1, 6)
        return ok ? 1 : min(300, 15 * pow(2, Double(failures - 1)))
    }
}

public enum SoundResponse {
    /// A successful transport response is not proof of audible playback.
    public static func validate(_ json: [String: Any]) throws {
        if let errors = json["serviceErrors"] as? [[String: Any]], !errors.isEmpty {
            throw RingError(.server, "Apple couldn't accept the request. Try again later.")
        }
        if let error = json["error"] as? String, !error.isEmpty {
            throw RingError(.server, "Apple couldn't accept the request. Try again later.")
        }
        guard !json.isEmpty else { throw RingError(.uncertain, "Couldn't confirm. The request may have gone through.") }
        if let code = json["statusCode"], String(describing: code) != "200" {
            throw RingError(.server, "Apple couldn't accept the request. Try again later.")
        }
    }
}

/// Status changes update immediately; unchanged data still needs a heartbeat
/// so a widget's previously rendered reading doesn't expire while polling works.
public struct AvailabilityWidgetReloadPolicy: Sendable {
    private var lastReload = Date.distantPast
    public init() {}
    public mutating func shouldReload(previous: AvailabilitySnapshot, current: AvailabilitySnapshot, now: Date) -> Bool {
        guard previous.devices != current.devices || previous.valid != current.valid
                || now.timeIntervalSince(lastReload) >= 10 else { return false }
        lastReload = now
        return true
    }
}
