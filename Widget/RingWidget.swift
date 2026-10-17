import WidgetKit
import SwiftUI
import AppIntents
import os

@main
struct RingWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
        RecentWidget()
    }
}

/// A timeline that shows a ring status until it expires, then the plain
/// widget, without running the extension again.
func statusTimeline<E: TimelineEntry>(_ entry: E, status: SharedStore.WidgetRingStatus?,
                                      cleared: (Date) -> E) -> Timeline<E> {
    guard let status else { return Timeline(entries: [entry], policy: .never) }
    return Timeline(entries: [entry, cleared(status.expires)], policy: .never)
}

// MARK: Favorites ("Ring")

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: .now, signedIn: true, favorites: [], hotkeyText: nil, hotkeyTargetID: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        completion(.now())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        // Nothing here changes on its own: the app reloads this timeline
        // whenever favorites, devices or the sign-in change, and the ring
        // intent when a ring starts and ends.
        let entry = FavoritesEntry.now()
        completion(statusTimeline(entry, status: entry.status, cleared: entry.cleared(at:)))
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        // Kind kept from 0.1 so widgets already on the desktop carry over.
        StaticConfiguration(kind: "RingWidget", provider: FavoritesProvider()) { entry in
            FavoritesView(entry: entry)
        }
        .configurationDisplayName("Ring")
        .description("Your favorite devices, one tap each.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Recent ("Last rings")

struct RecentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry { RecentEntry(date: .now, items: []) }
    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) { completion(.now()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        // Times like "2:31 AM" don't age, so refresh only for the day change
        // (or sooner, to clear a ring status).
        let entry = RecentEntry.now()
        var entries = [entry]
        if let status = entry.status { entries.append(entry.cleared(at: status.expires)) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentWidget", provider: RecentProvider()) { entry in
            RecentView(entry: entry)
        }
        .configurationDisplayName("Last rings")
        .description("What you rang lately. Tap one to ring it again.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
