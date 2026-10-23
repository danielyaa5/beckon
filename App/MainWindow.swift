import SwiftUI
import ServiceManagement
import KeyboardShortcuts

/// The main window, design 5's layout: a sidebar of device groups, device
/// cards to ring and star, hidden devices, ring history and settings. The
/// AirTags entry opens Find My's Items tab.
struct MainWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.hasCredentials {
                NavigationSplitView {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
                } detail: {
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                SignInScreen()
            }
        }
        .tint(Color.ringFill)
        .onAppear { model.willAppear() }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .history: HistoryPane()
        case .settings: SettingsPane()
        case .hidden: HiddenPane()
        default: DevicesPane(section: model.section)
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    private var selection: Binding<WindowSection?> {
        Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })
    }

    var body: some View {
        List(selection: selection) {
            Section("Devices") {
                row("All devices", "square.grid.2x2", .all, model.config.visibleDevices.count)
                row("Favorites", "star", .favorites, model.favorites.count)
                ForEach(model.groups, id: \.self) { group in
                    row(group, Self.symbol(group), .group(group), model.targets(in: .group(group)).count)
                }
                Button { model.openAirTagsInFindMy() } label: {
                    Label("AirTags", systemImage: "airtag")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Find My’s Items tab")
                if !model.config.hiddenIDs.isEmpty {
                    row("Hidden", "eye.slash", .hidden, model.config.hiddenIDs.count)
                }
            }
            Section("Activity") {
                row("Ring history", "clock.arrow.circlepath", .history, nil)
            }
            Section {
                row("Settings", "gearshape", .settings, nil)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if model.hasCredentials {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Signed in").font(.system(size: 12, weight: .semibold))
                    Text(model.appleID).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                    Text("Your password stays in this Mac's Keychain.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ section: WindowSection, _ count: Int?) -> some View {
        Label(title, systemImage: symbol)
            .badge(count ?? 0)
            .tag(section)
    }

    static func symbol(_ group: String) -> String {
        switch group {
        case "iPhone and iPad": "iphone"
        case "Mac": "laptopcomputer"
        case "Audio": "headphones"
        case "Watch": "applewatch"
        default: "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: Devices

private struct DevicesPane: View {
    @EnvironmentObject var model: AppModel
    let section: WindowSection
    @AppStorage("windowLayout") private var layout = "list"

    private var title: String {
        switch section {
        case .favorites: "Favorites"
        case .group(let g): g
        default: "All devices"
        }
    }

    var body: some View {
        let targets = model.targets(in: section)
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: title, subtitle: "Ring any of them. A star puts one in the menu and the widgets.") {
                Picker("Layout", selection: $layout) {
                    Image(systemName: "square.grid.2x2").tag("grid")
                    Image(systemName: "list.bullet").tag("list")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(model.refreshing ? "Loading…" : "Reload list", systemImage: "arrow.clockwise")
                }
                .help("Fetches your device names again, after you add or rename a device. Signs in to Apple once.")
                .disabled(model.refreshing)
            }
            if targets.isEmpty {
                EmptyNote(text: section == .favorites
                          ? "Star devices to pin them to the top of the menu and to the widgets."
                          : (model.refreshing ? "Loading your devices…" : "No devices here yet."))
            } else {
                ScrollView {
                    if layout == "list" {
                        VStack(spacing: 1) {
                            ForEach(targets) { DeviceRow(target: $0) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 12)], spacing: 12) {
                            ForEach(targets) { DeviceCard(target: $0) }
                        }
                    }
                }
            }
            if !model.status.isEmpty { StatusFooter() }
        }
        .padding(20)
    }
}

/// A device as a card.
struct DeviceCard: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: target.kind.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(target.device.online == false ? Color.secondary : Color.ringText)
                    .frame(width: 36, height: 36)
                    .background((target.device.online == false ? Color.secondary : Color.ringText).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                    Text(target.device.model).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                StarButton(target: target)
            }

            HStack(spacing: 8) {
                DeviceAvailabilityBadge(target: target)
                Spacer(minLength: 4)
                MoreMenu(target: target)
                RingButton(target: target)
            }
        }
        .padding(14)
        .frame(minHeight: 100, alignment: .top)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

/// The same, as a list row.
private struct DeviceRow: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.kind.symbol)
                .foregroundStyle(target.device.online == false ? Color.secondary : Color.ringText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(model.detail(target)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            DeviceAvailabilityBadge(target: target)
            StarButton(target: target)
            MoreMenu(target: target)
            RingButton(target: target)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.background)
    }
}

private struct DeviceAvailabilityBadge: View {
    let target: RingTarget

    var body: some View {
        if target.device.online == false {
            Label("Offline at last reload", systemImage: "wifi.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .fixedSize()
                .help("Apple reported this device offline when the list was loaded. Availability can change; use Reload list to update it.")
        }
    }
}

struct StarButton: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget

    var body: some View {
        let on = model.isFavorite(target)
        Button { model.toggleFavorite(target) } label: {
            Image(systemName: on ? "star.fill" : "star")
                .foregroundStyle(on ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(on ? "Remove from favorites" : "Add to favorites: the top of the menu and the widgets")
        .accessibilityLabel(on ? "Remove \(target.name) from favorites" : "Add \(target.name) to favorites")
    }
}

struct RingButton: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget

    var body: some View {
        Button {
            Task { await model.ring(target, source: "Window") }
        } label: {
            if model.ringingID == target.id {
                ProgressView().controlSize(.small).frame(width: 34)
            } else {
                Text("Ring").frame(minWidth: 34)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.ringFill)
        .controlSize(.small)
        .disabled(model.ringingID != nil)
        .accessibilityLabel("Ring \(target.name)")
    }
}

private struct MoreMenu: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget

    var body: some View {
        Menu {
            Button("Use for the shortcut key") { model.setHotkeyTarget(target) }
            Button(model.isHidden(target) ? "Show in the menu and widgets" : "Hide from the menu and widgets") {
                model.setHidden(target, !model.isHidden(target))
            }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(target.link.absoluteString, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More for \(target.name)")
    }
}

// MARK: Hidden

private struct HiddenPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Hidden", subtitle: "Left out of the menu, the palette's first results and the widgets. They stay in Find My.") {}
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.targets(in: .hidden)) { t in
                        HStack(spacing: 12) {
                            Image(systemName: t.kind.symbol).frame(width: 24).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name).font(.system(size: 13, weight: .semibold))
                                Text(t.device.model).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Show") { model.setHidden(t, false) }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(.background)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
    }
}

// MARK: History

private struct HistoryPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(title: "Ring history", subtitle: "From the menu, palette, shortcut key, widgets, links and Shortcuts") {
                Button("Clear") { model.clearHistory() }.disabled(model.history.isEmpty)
            }
            if model.history.isEmpty {
                EmptyNote(text: "Nothing rung yet.")
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(model.history) { event in
                            HStack(spacing: 12) {
                                Image(systemName: event.kind.symbol).frame(width: 24).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.name).font(.system(size: 13, weight: .semibold))
                                    Text(event.ok ? "Sent from \(event.source.lowercased())" : (event.note ?? "Failed"))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(event.ok ? Color.secondary : Color.orange)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                if let t = model.config.target(id: event.target) {
                                    RingButton(target: t)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(.background)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .onAppear { model.reloadHistory() }
    }
}

// MARK: Settings

private struct SettingsPane: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(DockPolicy.alwaysKey) private var alwaysInDock = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar and Dock") {
                Text("Beckon lives in the menu bar. This window adds a Dock icon while it's open.")
                    .foregroundStyle(.secondary)
                Toggle("Keep the Dock icon after closing this window", isOn: $alwaysInDock)
                    .onChange(of: alwaysInDock) { DockPolicy.windowOpened() }
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { setOpenAtLogin(openAtLogin) }
                if let loginError { Text(loginError).foregroundStyle(.orange) }
            }

            Section("Shortcut keys") {
                KeyboardShortcuts.Recorder("Ring:", name: .ringFavorite) { _ in Hotkeys.syncText() }
                Picker("Rings", selection: hotkeyTarget) {
                    Text("First favorite").tag(String?.none)
                    ForEach(model.config.allTargets.filter { !model.isHidden($0) }) { t in
                        Text(t.name).tag(String?.some(t.id))
                    }
                }
                KeyboardShortcuts.Recorder("Open the ring palette:", name: .openPalette)
                Text("The palette searches every device: type a few letters and press Return.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Device list") {
                Text("Beckon signs in to Apple only to ring, and to load your device names when you sign in or press Reload. It doesn't check on your devices in the background or keep battery or location data.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent(model.listLoadedText) {
                    Button(model.refreshing ? "Loading…" : "Reload list") { Task { await model.refresh() } }
                        .disabled(model.refreshing)
                }
            }

            Section("Links") {
                LabeledContent("Ring a device", value: "beckon://ring/<name>")
                LabeledContent("Open the palette", value: "beckon://palette")
                Text("For Raycast, Alfred, Stream Deck or a bookmark. Each card's ⋯ menu copies its own link.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Account") {
                LabeledContent("Apple Account", value: model.appleID)
                Button("Sign out", role: .destructive) { model.signOut() }
            }

            Section {
                Button("Show walkthrough…") { OnboardingController.shared.show() }
                UpdateSettings()
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyTarget: Binding<String?> {
        Binding(get: { model.config.hotkeyTarget }, set: { id in
            model.setHotkeyTarget(id.flatMap(model.config.target(id:)))
        })
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change it: \(error.localizedDescription)"
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Shared bits

private struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            trailing
        }
    }
}

private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatusFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 6) {
            if model.ringingID != nil || model.refreshing { ProgressView().controlSize(.small) }
            Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

