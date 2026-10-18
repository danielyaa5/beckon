import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    static let completedKey = "walkthroughCompleted"
    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible == true }

    static func shouldShow(hasCredentials: Bool) -> Bool {
        !hasCredentials && !UserDefaults.standard.bool(forKey: completedKey)
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 560, height: min(650, (NSScreen.main?.visibleFrame.height ?? 710) - 60))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Welcome to Beckon"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: WalkthroughView(finish: { [weak self] in self?.window?.close() })
            .environmentObject(AppModel.shared))
        host.sizingOptions = []
        window.contentViewController = host
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.delegate = self
        self.window = window
        window.center()
        DockPolicy.windowOpened()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if !Screenshots.active { UserDefaults.standard.set(true, forKey: Self.completedKey) }
        window = nil
        Task { MainWindowController.shared.show() }
    }
}

struct BeckonMark: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable().interpolation(.high).frame(width: size, height: size)
            .accessibilityLabel("Beckon")
    }
}

struct SignInScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BeckonMark()
                SignInForm(large: true)
                    .padding(28)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator.opacity(0.6)))
                Button("New to Beckon? Take a quick tour") { OnboardingController.shared.show() }
                    .buttonStyle(.link)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct WalkthroughView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    let finish: () -> Void
    private let labels = ["Welcome", "Sign in", "Widgets", "Ready"]

    init(initialStep: Int = 0, finish: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.finish = finish
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BECKON").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2)
                Spacer()
                Button("Skip tour", action: finish).buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(model.refreshing)
            }
            .padding(.top, 36).padding(.horizontal, 32)

            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule().fill(index <= step ? Color.ringFill : Color.primary.opacity(0.1)).frame(height: 3)
                }
            }.padding(.horizontal, 32).padding(.top, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(step + 1) OF 4 · \(labels[step].uppercased())")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    page
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }.disabled(model.refreshing)
                }
                Spacer()
                if step == 1 && !model.hasCredentials {
                    Button("Sign in later") { step += 1 }.disabled(model.refreshing)
                } else {
                    Button(step == 3 ? "Open Beckon" : (step == 0 ? "Get started" : "Continue")) {
                        if step == 3 { finish() } else { step += 1 }
                    }
                    .buttonStyle(.borderedProminent).tint(Color.ringFill).controlSize(.large)
                }
            }.padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.ringFill)
        .onChange(of: model.hasCredentials) { _, signedIn in
            if signedIn && step == 1 { step = 2 }
        }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0:
            BeckonMark(size: 88)
            title("Find your devices\nwith a tap.")
            Text("Find your iPhone, iPad, Mac or AirPods with a sound, even when your phone is on silent.")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            tip("speaker.wave.2", "Ring from anywhere", "Use the menu bar, a keyboard shortcut or a desktop widget.")
            tip("lock.shield", "Your sign-in stays here", "Your Apple Account password is saved in this Mac’s Keychain.")
            Text("Beckon is an independent app and isn’t affiliated with Apple.")
                .font(.footnote).foregroundStyle(.secondary)
        case 1:
            if model.hasCredentials {
                title("You're connected.")
                tip("checkmark.circle", "Your devices are ready", "Next, pick favorites and add a widget to your desktop.")
            } else {
                SignInForm(large: true)
                    .padding(24).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity)
            }
        case 2:
            title("One tap from\nyour desktop.")
            widgetPreview
            tip("star", "1. Choose your favorites", "In Beckon, click the star beside each device you want in your widget.")
            tip("rectangle.badge.plus", "2. Add the widget", "Right-click an empty spot on your desktop, choose Edit Widgets, then search for Beckon.")
            tip("hand.tap", "3. Pick Ring and place it", "Choose a size, drag it onto the desktop and click Done. Tap Ring whenever you need a device.")
            Text("Last rings lets you ring a recent device again. Your Mac needs internet access to send a ring; device widgets also work with Beckon closed.")
                .font(.footnote).foregroundStyle(.secondary)
        default:
            title("Ready when\nyou need a ring.")
            tip("menubar.rectangle", "Look in the menu bar", "Click Beckon’s phone-and-waves icon to search your devices or ring a favorite.")
            tip("keyboard", "Keep a shortcut handy", "Open the ring palette with Control–Option–Space. Change your shortcuts in Settings.")
            tip("airtag", "Looking for an AirTag?", "Open AirTags in Beckon. Your Mac must be awake, unlocked and nearby, with Accessibility and Screen Recording allowed. AirTags ring through the app.")
            Text("You can revisit this tour from Settings → Show walkthrough.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func title(_ value: String) -> some View {
        Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tip(_ symbol: String, _ heading: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.ringText)
                .frame(width: 32, height: 32).background(Color.ringFill.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(heading).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var widgetPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone").font(.title2).foregroundStyle(Color.ringText)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your iPhone").font(.system(size: 14, weight: .semibold))
                Text("A favorite device").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Ring").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(.white).background(Color.ringFill, in: Capsule())
        }
        .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: a Ring widget with a favorite iPhone")
    }
}
