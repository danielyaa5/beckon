#if BECKON_QA
import AppKit
import SwiftUI
import FindMyRingKit

@MainActor
enum AvailabilityQAController {
    static var window: NSWindow?
    static func show() {
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 190), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Beckon QA · fictional devices only"
        w.contentView = NSHostingView(rootView: VStack(spacing: 16) {
            Text("Test iPhone availability").font(.headline)
            HStack {
                Button("Online") { AvailabilityQA.set(.online) }
                Button("Offline") { AvailabilityQA.set(.offline) }
                Button("Needs refresh") { AvailabilityQA.set(.unknown) }
            }
            Text("No Apple connection or real sound requests.").font(.caption)
            Button("Open device window") { MainWindowController.shared.show() }
        }.padding())
        w.center(); w.makeKeyAndOrderFront(nil); window = w
    }
}
#endif
