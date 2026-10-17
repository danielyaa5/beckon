import Foundation

/// What sort of thing a device is, for its icon and grouping.
enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case phone, tablet, mac, watch, headphones, earbuds, airTag, other

    init(model: String, deviceClass: String) {
        let m = (model + " " + deviceClass).lowercased()
        if m.contains("iphone") { self = .phone }
        else if m.contains("ipad") { self = .tablet }
        else if m.contains("watch") { self = .watch }
        else if m.contains("mac") || m.contains("imac") { self = .mac }
        else if m.contains("airpods max") || m.contains("studio") || m.contains("solo") { self = .headphones }
        else if m.contains("airpods") || m.contains("beats") || m.contains("powerbeats") { self = .earbuds }
        else { self = .other }
    }

    var symbol: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .mac: "laptopcomputer"
        case .watch: "applewatch"
        case .headphones: "headphones"
        case .earbuds: "earbuds"
        case .airTag: "airtag"
        case .other: "dot.radiowaves.left.and.right"
        }
    }

    /// The window's sidebar groups.
    var group: String {
        switch self {
        case .phone, .tablet: "iPhone and iPad"
        case .mac: "Mac"
        case .headphones, .earbuds: "Audio"
        case .watch: "Watch"
        case .airTag: "AirTags"
        case .other: "Other"
        }
    }
}

/// Anything the app can ring: a device (through iCloud) or an AirTag (by
/// driving the Mac's Find My app).
struct RingTarget: Identifiable, Hashable, Sendable {
    static let airTagPrefix = "airtag:"

    let id: String
    let name: String
    let kind: DeviceKind
    let device: SharedStore.CachedDevice?

    var isAirTag: Bool { device == nil }

    static func device(_ d: SharedStore.CachedDevice) -> RingTarget {
        RingTarget(id: d.id, name: d.name, kind: d.kind, device: d)
    }

    static func airTag(_ name: String) -> RingTarget {
        RingTarget(id: airTagPrefix + name, name: name, kind: .airTag, device: nil)
    }

    /// `beckon://ring/<name>?id=<id>`: the name keeps it readable, the id
    /// (which the link handler reads first) keeps two devices with one name,
    /// or a device named like an AirTag, from ringing the wrong one.
    var link: URL {
        var c = URLComponents()
        c.scheme = "beckon"
        c.host = "ring"
        c.path = "/" + name
        c.queryItems = [URLQueryItem(name: "id", value: id)]
        return c.url ?? URL(string: "beckon://open")!
    }
}

/// The short texts the menu, window and widgets show.
enum Describe {
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    /// What a target is: "iPhone 18 Pro", or "AirTag".
    static func detail(_ t: RingTarget) -> String {
        guard let d = t.device else { return "AirTag" }
        return d.model.isEmpty ? "Device" : d.model
    }
}
