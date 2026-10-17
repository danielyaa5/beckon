import Foundation

/// A device from Find My that can be rung.
public struct FoundDevice: Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Apple's display name for the model, e.g. "iPhone 18 Pro".
    public let model: String
    public let deviceClass: String
    public let isOnline: Bool
    public let canRing: Bool
    /// 0...1, or nil when Apple reports no reading (common for AirPods).
    public let batteryLevel: Double?
    /// Apple's "Charging" / "NotCharging" / "Charged" / "Unknown".
    public let batteryStatus: String?
    public let location: Location?

    public var isCharging: Bool { batteryStatus == "Charging" }

    /// Where Find My last placed the device.
    public struct Location: Sendable, Codable, Hashable {
        public let latitude: Double
        public let longitude: Double
        /// Horizontal accuracy in meters.
        public let accuracy: Double
        public let timestamp: Date

        public init(latitude: Double, longitude: Double, accuracy: Double, timestamp: Date) {
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.timestamp = timestamp
        }
    }

    public init(
        id: String, name: String, model: String, deviceClass: String,
        isOnline: Bool, canRing: Bool,
        batteryLevel: Double? = nil, batteryStatus: String? = nil, location: Location? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.deviceClass = deviceClass
        self.isOnline = isOnline
        self.canRing = canRing
        self.batteryLevel = batteryLevel
        self.batteryStatus = batteryStatus
        self.location = location
    }
}

/// An error with a message fit to show the user.
public struct RingError: Error, CustomStringConvertible, Sendable {
    public enum Kind: Sendable {
        case badCredentials    // Apple rejected the email/password
        case accountLocked     // Apple reports the account locked
        case twoFactorWanted   // Apple would not grant password-only Find My
        case network           // could not reach Apple
        case server            // unexpected response
    }
    public let kind: Kind
    public let message: String
    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
    public var description: String { message }
}
