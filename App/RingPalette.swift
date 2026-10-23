import AppKit
import SwiftUI

/// The Spotlight-style ring palette from design 3: a shortcut key opens it,
/// you type a few letters and press Return. A panel that takes typing without
/// pulling the app (or a Dock icon) forward.
@MainActor
final class RingPalette: NSObject, NSWindowDelegate {
    static let shared = RingPalette()

    private var panel: PalettePanel?

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        // A new view each time, so it opens with an empty search.
        let host = NSHostingView(rootView: PaletteView(close: { [weak self] in self?.close() })
            .environmentObject(AppModel.shared))
        panel.contentView = host
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.22 - size.height,
                                  width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        AppModel.shared.willAppear()
    }

    func close() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func make() -> PalettePanel {
        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                 styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }
}

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct PaletteView: View {
    @EnvironmentObject var model: AppModel
    let close: () -> Void

    @State private var query: String
    @State private var selected = 0
    @FocusState private var focused: Bool

    private let autofocus: Bool

    /// `query` and `autofocus` are set only for screenshots; the palette
    /// opens empty, with the cursor in the search field.
    init(query: String = "", autofocus: Bool = true, close: @escaping () -> Void) {
        _query = State(initialValue: query)
        self.autofocus = autofocus
        self.close = close
    }

    private var matches: [RingTarget] { model.search(query) }
    private var results: [RingTarget] { Array(matches.prefix(8)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Ring a device", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onSubmit { ringSelected(keepOpen: false) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onChange(of: query) { selected = 0 }
                if let key = Hotkeys.text(for: .openPalette) { Keycap(text: key) }
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            Divider()

            if results.isEmpty {
                Text(model.hasCredentials ? "No matches" : "Sign in from the menu bar first")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, target in
                        row(target, index: index)
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Text("↩ ring · ⌘↩ ring and keep open · ⌘S star")
                Spacer()
                let hidden = matches.filter(model.isHidden).count
                Text("\(matches.count) match\(matches.count == 1 ? "" : "es")" + (hidden > 0 ? " · \(hidden) hidden" : ""))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 36)
        }
        .frame(width: 600)
        .background(alignment: .topLeading) {
            // Shortcuts for the selected row; invisible but live.
            Group {
                Button("Ring and keep open") { ringSelected(keepOpen: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Star") { if let t = current { model.toggleFavorite(t) } }
                    .keyboardShortcut("s", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        // The panel's hidden title bar otherwise leaves an empty band on top.
        .ignoresSafeArea()
        .onAppear { focused = autofocus }
    }

    private var current: RingTarget? { results.indices.contains(selected) ? results[selected] : nil }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    private func ringSelected(keepOpen: Bool) {
        guard let t = current else { return }
        if !keepOpen { close() }
        Task { await model.ringWithHUD(t, source: "Palette") }
    }

    @ViewBuilder private func row(_ t: RingTarget, index: Int) -> some View {
        let isSelected = index == selected
        Button {
            selected = index
            ringSelected(keepOpen: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: t.kind.symbol)
                    .font(.system(size: 17))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(t.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if model.isFavorite(t) { Image(systemName: "star.fill").font(.system(size: 10)) }
                    }
                    Text(model.isHidden(t) ? "Hidden · " + model.detail(t) : model.detail(t))
                        .font(.system(size: 12))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                Spacer()
                if model.ringingID == t.id {
                    ProgressView().controlSize(.small)
                } else if isSelected {
                    Text("↩ Ring").font(.system(size: 12, weight: .semibold))
                } else if index < 9 {
                    Text("⌘\(index + 1)").font(.system(size: 12, weight: .medium)).opacity(0.7)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.ringFill : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .onHover { if $0 { selected = index } }
    }
}
