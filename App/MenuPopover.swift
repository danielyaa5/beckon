import SwiftUI

/// The menu-bar popover, design 3: search on top, favorites with ⌘1–⌘9,
/// recent rings, and the global shortcut key.
struct MenuPopover: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private var results: [RingTarget] { Array(model.search(query).prefix(7)) }

    /// Favorites, or the first devices while nothing is starred.
    private var quickList: [RingTarget] {
        let favs = model.favorites
        return favs.isEmpty ? Array(model.config.visibleDevices.prefix(6).map(RingTarget.device)) : Array(favs.prefix(9))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.hasCredentials {
                SignInForm()
            } else {
                searchField
                if query.isEmpty {
                    quickSection
                    airTagsRow
                    recentSection
                    hotkeyLine
                } else {
                    resultsSection
                }
                // Always there, so the menu doesn't grow while it's open
                // (a MenuBarExtra window can clip what appears later).
                statusLine
            }
            footer
        }
        .padding(10)
        .frame(width: 340)
        .onAppear {
            model.willAppear()
            searchFocused = true
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search devices", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { ringResult(selected) }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .onChange(of: query) { selected = 0 }
            Text("⌘K").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .background {
            Button("Search") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if results.isEmpty {
                Text("No matches").foregroundStyle(.secondary).padding(8)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, t in
                let isSelected = index == selected
                Button { ringResult(index) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.kind.symbol).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(model.isHidden(t) ? "Hidden · " + model.detail(t) : model.detail(t))
                                .font(.system(size: 11.5)).opacity(0.85).lineLimit(1)
                        }
                        Spacer()
                        if model.ringingID == t.id {
                            ProgressView().controlSize(.small)
                        } else if isSelected {
                            Text("↩ Ring").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.ringFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { selected = index } }
            }
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    private func ringResult(_ index: Int) {
        guard results.indices.contains(index) else { return }
        let t = results[index]
        Task { await model.ring(t, source: "Menu") }
    }

    // MARK: Favorites

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(text: model.favorites.isEmpty ? "Devices" : "Favorites")
                Spacer()
                if model.favorites.isEmpty {
                    Text("Star some in the window").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if model.config.devices.isEmpty {
                Text(model.refreshing ? "Loading your devices…" : "No devices yet. Refresh below.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
            }
            ForEach(Array(quickList.enumerated()), id: \.element.id) { index, t in
                QuickRow(target: t, number: index + 1)
            }
        }
    }

    // MARK: Recent

    @ViewBuilder private var recentSection: some View {
        let recent = Array(model.history.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Divider().padding(.bottom, 4)
                SectionLabel(text: "Recent")
                ForEach(recent) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.ok ? "clock" : "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(event.ok ? Color.secondary : Color.orange)
                            .frame(width: 16)
                        Text(event.name).font(.system(size: 12.5)).lineLimit(1)
                        Spacer()
                        Text(Self.when(event.date)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        if let t = model.config.target(id: event.target) {
                            Button("Again") { Task { await model.ring(t, source: "Menu") } }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.ringText)
                                .disabled(model.ringingID != nil)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                }
            }
        }
    }

    static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// A fixed place for AirTags: they don't come from iCloud, so they need
    /// their own way in (the Find My scan in the window).
    private var airTagsRow: some View {
        let count = model.config.airTags.count
        return Button { MainWindowController.shared.show(.airTags) } label: {
            HStack(spacing: 10) {
                Image(systemName: "airtag")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ringText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(count == 0 ? "Find your AirTags" : "AirTags (\(count))")
                        .font(.system(size: 13, weight: .semibold))
                    Text(count == 0 ? "Reads them from the Find My app" : "Star one to put it above, or search for it")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(Color.ringFill.opacity(count == 0 ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Shortcut key and footer

    @ViewBuilder private var hotkeyLine: some View {
        if let key = Hotkeys.text(for: .ringFavorite), let t = model.hotkeyTarget {
            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.bottom, 6)
                HStack(spacing: 6) {
                    Keycap(text: key)
                    Text("rings \(t.name) from anywhere").font(.system(size: 11.5)).lineLimit(1)
                    Spacer()
                    Button("Change") { MainWindowController.shared.show(.settings) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.ringText)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// The latest outcome, or when the list was last loaded. One line, so the
    /// menu keeps its height.
    private var statusLine: some View {
        HStack(spacing: 6) {
            if model.refreshing || model.ringingID != nil { ProgressView().controlSize(.mini) }
            Text(statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(model.status.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.status)
        }
        .frame(height: 16)
        .padding(.horizontal, 8)
    }

    private var statusText: String {
        if !model.status.isEmpty { return model.status }
        return model.refreshing ? "Loading your device list…" : ""
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Button("Open Beckon…") { MainWindowController.shared.show() }
                    .keyboardShortcut("o", modifiers: .command)
                Spacer()
                if model.hasCredentials {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload the device list, after adding or renaming a device. Signs in to Apple once.")
                    .disabled(model.refreshing)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12.5))
            .padding(.horizontal, 6)
        }
    }
}

/// One favorite: click (or ⌘ + its number) rings it.
private struct QuickRow: View {
    @EnvironmentObject var model: AppModel
    let target: RingTarget
    /// 1–9: its ⌘-number shortcut.
    let number: Int
    @State private var hovering = false

    var body: some View {
        Button { Task { await model.ring(target, source: "Menu") } } label: {
            HStack(spacing: 10) {
                Image(systemName: target.kind.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ringText)
                    .frame(width: 18)
                Text(target.name).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(model.detail(target)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                if model.ringingID == target.id {
                    ProgressView().controlSize(.small).frame(width: 30)
                } else {
                    Keycap(text: "⌘\(number)").frame(minWidth: 30)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        .onHover { hovering = $0 }
        .help("Ring \(target.name)")
        .disabled(model.ringingID != nil)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }
}

/// Sign-in, used by the menu and the window.
struct SignInForm: View {
    @EnvironmentObject var model: AppModel
    var large = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in with your Apple Account")
                .font(.system(size: large ? 22 : 14, weight: .bold))
            Text("Use your password. No code from your phone. It stays in this Mac's Keychain, and only this app and its widgets can read it.")
                .font(.system(size: large ? 13 : 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Apple Account email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            Button(action: submit) {
                Text(model.refreshing ? "Signing in…" : "Sign in and load devices")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ringFill)
            .controlSize(large ? .large : .regular)
            .disabled(email.isEmpty || password.isEmpty || model.refreshing)
        }
        .frame(maxWidth: large ? 420 : .infinity)
        .onAppear { email = model.appleID }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task {
            await model.signIn(appleID: email, password: password)
            password = ""
        }
    }
}
