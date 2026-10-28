import WidgetKit
import SwiftUI
import os
import FindMyRingKit

// The widgets' views and entries. Compiled into the widget extension, which
// shows them, and into the app, which draws them only for the screenshots in
// the README and on the website (`Beckon --screenshots <folder>`).

// MARK: Shared widget bits

/// The widget's accent, picked per appearance (widgets don't resolve dynamic
/// AppKit colors reliably).
struct WidgetColors {
    let scheme: ColorScheme
    var text: Color {
        scheme == .dark ? Color(red: 1.0, green: 0.58, blue: 0.36) : Color(red: 0.69, green: 0.23, blue: 0.04)
    }
    var fill: Color { .ringFill }
}

/// A filled button face that stays readable when macOS dims desktop widgets.
/// In the dimmed (vibrant) style the orange fill turns pale grey and white
/// text on it disappears, so outside full color the label uses the primary
/// color on a light tint instead.
struct FilledFace<S: Shape>: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    let shape: S
    var fill: Color = .ringFill

    @ViewBuilder func body(content: Content) -> some View {
        if mode == .fullColor {
            content.foregroundStyle(.white).background(fill, in: shape)
        } else {
            content.foregroundStyle(.primary).background(Color.primary.opacity(0.14), in: shape)
        }
    }
}

extension View {
    func filledFace<S: Shape>(_ shape: S, fill: Color = .ringFill) -> some View {
        modifier(FilledFace(shape: shape, fill: fill))
    }
}

/// How a ring button tells you the tap went through: "Sending…" while the
/// widget signs in and sends the ring, then "Sent" (green) or "Didn't ring"
/// for a few seconds. Don't add `invalidatableContent()` to these labels: in
/// 0.4.2 it made macOS treat taps on the button as taps on the widget
/// background, which open the app instead of ringing.
typealias RingState = SharedStore.WidgetRingStatus.State

extension RingState {
    var symbol: String {
        switch self {
        case .ringing: "ellipsis"
        case .sent: "checkmark"
        case .failed, .uncertain: "exclamationmark"
        case .needsRefresh: "arrow.clockwise"
        }
    }
    var title: String {
        switch self {
        case .ringing: "Sending…"
        case .sent: "Request sent"
        case .failed: "Couldn't send"
        case .uncertain: "Couldn't confirm"
        case .needsRefresh: "Needs refresh"
        }
    }
    /// The line under a device's name in the list.
    var detail: String {
        switch self {
        case .ringing: "Sending…"
        case .sent: "Request sent · playback unconfirmed"
        case .failed: "Couldn't send · see Beckon"
        case .uncertain: "Couldn't confirm · see Beckon"
        case .needsRefresh: "Needs refresh"
        }
    }
    var fill: Color { self == .sent ? Color(red: 0.16, green: 0.6, blue: 0.3) : .ringFill }
}

/// Rings from the widget directly: an App Intent in the widget's own process.
struct WidgetRingButton<Label: View>: View {
    let target: RingTarget
    var disabled = false
    @ViewBuilder let label: Label

    var body: some View {
        #if WIDGET_EXTENSION
        Button(intent: RingDeviceIntent(deviceID: target.id, deviceName: target.name)) { label }
            .buttonStyle(.plain)
            .disabled(disabled)
        #else
        // The app draws these views only for screenshots.
        label
        #endif
    }
}

struct WidgetStatusRefresh: View {
    var body: some View {
        #if WIDGET_EXTENSION
        Button(intent: RefreshDeviceStatusIntent()) {
            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Refresh device status")
        #else
        Image(systemName: "arrow.clockwise").font(.system(size: 11))
        #endif
    }
}

struct WidgetHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct WidgetTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: Favorites ("Ring")

struct FavoritesEntry: TimelineEntry {
    var date: Date
    let signedIn: Bool
    let favorites: [RingTarget]
    let hotkeyText: String?
    let hotkeyTargetID: String?
    var status: SharedStore.WidgetRingStatus? = nil
    var availability: AvailabilitySnapshot = SharedStore.availability()

    func state(of t: RingTarget) -> RingState? { status?.target == t.id ? status?.state : nil }

    func cleared(at date: Date) -> FavoritesEntry {
        var e = self
        e.date = date
        if let status, status.expires <= date { e.status = nil }
        return e
    }

    static func now() -> FavoritesEntry {
        let config = SharedStore.load()
        let signedIn = SharedStore.password(appleID: config.appleID ?? "") != nil
        let entry = FavoritesEntry(date: .now, signedIn: signedIn, favorites: config.favorites,
                                   hotkeyText: config.hotkeyText,
                                   hotkeyTargetID: config.hotkeyRingTarget?.id,
                                   status: SharedStore.widgetRingStatus())
        SharedStore.log.notice("Widget: signed in \(signedIn, privacy: .public), \(entry.favorites.count, privacy: .public) favorites")
        return entry
    }
}

struct FavoritesView: View {
    var entry: FavoritesEntry
    /// Set only when the app draws this view for screenshots; a real widget
    /// reads its size from the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    @Environment(\.colorScheme) private var scheme

    private var colors: WidgetColors { WidgetColors(scheme: scheme) }

    var body: some View {
        Group {
            if !entry.signedIn {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetTitle(text: "Beckon")
                    WidgetHint(text: "Open Beckon from the menu bar to sign in.")
                    Spacer(minLength: 0)
                }
            } else if entry.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetTitle(text: "Beckon")
                    WidgetHint(text: "Star devices in Beckon to show them here.")
                    Spacer(minLength: 0)
                }
            } else if family == .systemSmall {
                small
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "beckon://open"))
    }

    private var hero: RingTarget? {
        entry.favorites.first { $0.id == entry.hotkeyTargetID } ?? entry.favorites.first
    }

    /// Design 3's small widget: one device, big, with the shortcut key.
    private var small: some View {
        let hero = self.hero ?? entry.favorites[0]
        return VStack(alignment: .leading, spacing: 4) {
            HStack { WidgetTitle(text: "Beckon"); Spacer(); WidgetStatusRefresh() }
            Spacer(minLength: 0)
            Text(hero.name)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(entry.availability.state(for: hero.id, at: entry.date).title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            WidgetRingButton(target: hero, disabled: entry.availability.state(for: hero.id, at: entry.date) != .online || entry.state(of: hero) == .ringing) {
                let state = entry.state(of: hero)
                HStack(spacing: 6) {
                    if let state {
                        Image(systemName: state.symbol).font(.system(size: 12, weight: .bold))
                        Text(state.title).font(.system(size: 13, weight: .bold))
                    } else {
                        Text("Ring").font(.system(size: 13, weight: .bold))
                        if hero.id == entry.hotkeyTargetID, let key = entry.hotkeyText {
                            Text(key).font(.system(size: 11)).opacity(0.9)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .filledFace(RoundedRectangle(cornerRadius: 10), fill: entry.availability.state(for: hero.id, at: entry.date) == .online ? state?.fill ?? .ringFill : .gray)
            }
        }
    }

    /// Medium and large: favorites as rows, each with its own ring button.
    private var list: some View {
        let count = family == .systemLarge ? 8 : 3
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetTitle(text: "Beckon")
                Spacer()
                WidgetStatusRefresh()
            }
            ForEach(Array(entry.favorites.prefix(count))) { t in
                WidgetRingButton(target: t, disabled: entry.availability.state(for: t.id, at: entry.date) != .online || entry.state(of: t) == .ringing) {
                    let state = entry.state(of: t)
                    HStack(spacing: 10) {
                        Image(systemName: t.kind.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(entry.availability.state(for: t.id, at: entry.date) == .online ? colors.text : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(state?.detail ?? entry.availability.state(for: t.id, at: entry.date).title)
                                .font(.system(size: 10.5, weight: state == nil ? .regular : .semibold))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: state?.symbol ?? "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 26)
                            .filledFace(Capsule(), fill: entry.availability.state(for: t.id, at: entry.date) == .online ? state?.fill ?? .ringFill : .gray)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Recent ("Last rings")

struct RecentEntry: TimelineEntry {
    struct Item: Identifiable {
        let id: UUID
        let event: SharedStore.RingEvent
        let target: RingTarget?
    }
    var date: Date
    let items: [Item]
    var status: SharedStore.WidgetRingStatus? = nil
    var availability: AvailabilitySnapshot = SharedStore.availability()

    func state(of t: RingTarget?) -> RingState? {
        guard let t, status?.target == t.id else { return nil }
        return status?.state
    }

    func cleared(at date: Date) -> RecentEntry {
        var e = self
        e.date = date
        if let status, status.expires <= date { e.status = nil }
        return e
    }

    static func now() -> RecentEntry {
        let config = SharedStore.load()
        var seen = Set<String>()
        let items = SharedStore.history().filter { seen.insert($0.target).inserted }.prefix(6).map {
            Item(id: $0.id, event: $0, target: config.target(id: $0.target))
        }
        return RecentEntry(date: .now, items: Array(items), status: SharedStore.widgetRingStatus())
    }
}

struct RecentView: View {
    var entry: RecentEntry
    /// Set only when the app draws this view for screenshots; a real widget
    /// reads its size from the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = WidgetColors(scheme: scheme)
        let count = family == .systemSmall ? 3 : (family == .systemLarge ? 6 : 3)
        VStack(alignment: .leading, spacing: 6) {
            HStack { WidgetTitle(text: "Last rings"); Spacer(); WidgetStatusRefresh() }
            if entry.items.isEmpty {
                WidgetHint(text: "Rings you send from the menu, palette, shortcut key or widgets show up here.")
            }
            ForEach(entry.items.prefix(count)) { item in
                if let target = item.target {
                    WidgetRingButton(target: target, disabled: entry.availability.state(for: target.id, at: entry.date) != .online || entry.state(of: target) == .ringing) { row(item, colors: colors, canRing: true) }
                } else {
                    row(item, colors: colors, canRing: false)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "beckon://open"))
    }

    private func row(_ item: RecentEntry.Item, colors: WidgetColors, canRing: Bool) -> some View {
        let state = entry.state(of: item.target)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.event.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let state {
                    Text(state.detail)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(state == .failed ? Color.orange : Color.secondary)
                } else {
                    Text(Self.when(item.event.date) + (item.event.ok ? " · request sent" : item.event.uncertain == true ? " · couldn't confirm" : " · couldn't send"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.event.ok ? Color.secondary : Color.orange)
                }
            }
            Spacer(minLength: 4)
            if canRing && family != .systemSmall {
                Text(state?.title ?? (entry.availability.state(for: item.target?.id ?? "", at: entry.date) == .online ? "Again" : entry.availability.state(for: item.target?.id ?? "", at: entry.date).title))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(colors.text)
                    .widgetAccentable()
            }
        }
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
