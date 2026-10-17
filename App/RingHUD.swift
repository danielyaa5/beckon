import AppKit
import SwiftUI

/// The "Ringing…" confirmation in the middle of the screen, like the volume
/// overlay: shown for rings started away from the menu (shortcut key,
/// palette, links, Shortcuts). Never takes clicks or focus.
@MainActor
final class RingHUD {
    static let shared = RingHUD()

    enum Message {
        case ringing(RingTarget)
        case sent(RingTarget)
        case failed(String?, String)
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: Message) {
        let panel = self.panel ?? make()
        self.panel = panel

        let view: HUDView
        let delay: Double
        switch message {
        case .ringing(let t):
            view = HUDView(symbol: "speaker.wave.2.fill", title: "Ringing \(t.name)",
                           detail: t.isAirTag ? "Find My opens for a moment" : "Signing in to iCloud…", busy: true)
            delay = 45
        case .sent(let t):
            view = HUDView(symbol: "speaker.wave.2.fill", title: "Ringing \(t.name)",
                           detail: t.isAirTag ? "Sent from this Mac" : "Sent · Apple will email you", busy: false)
            delay = 1.8
        case .failed(let name, let why):
            view = HUDView(symbol: "exclamationmark.triangle.fill", title: name.map { "Couldn't ring \($0)" } ?? "Nothing to ring",
                           detail: why, busy: false)
            delay = 4
        }
        panel.contentView = NSHostingView(rootView: view)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 120, y: frame.minY + frame.height * 0.22))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 240),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let detail: String
    let busy: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.14)).frame(width: 76, height: 76)
                Image(systemName: symbol).font(.system(size: 32, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small).tint(.white) }
                Text(detail).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(3)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 220, height: 220)
        .background(Color.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(width: 240, height: 240)
    }
}
