# Beckon

A small macOS (and, later, iOS) app that rings your Apple devices
through Find My — one tap, one key or one word to make a misplaced iPhone play a
sound, even on silent. Built 2026-10-15 as "Find My Ring"; redesigned in 0.3.0
and renamed Beckon in 0.4.1 (both 2026-10-16).

![Typing "air" in Beckon's palette rings AirPods; clicking Ring on the desktop widget shows Sending, then Sent](docs/demo.gif)

**Website:** https://danielyaa5.github.io/beckon/

## Download

**[Download Beckon for Mac](https://github.com/danielyaa5/beckon/releases/latest/download/Beckon.dmg)**
(macOS 14 or later, Apple silicon or Intel; signed and notarized by Apple).

1. Open **Beckon.dmg**. Drag **Beckon** onto **Applications** in the installer window, then open Beckon from Applications. When Beckon opens, it offers to move the downloaded DMG to Trash and ejects the installer disk. Closing the Finder window alone does not eject it.
2. Click the Beckon icon in the menu bar and sign in with your Apple Account
   email and password. Apple checks the password before Beckon saves it, in
   your Mac's Keychain.
3. Star the devices you ring most, and add the **Ring** widget from the
   desktop's Edit Widgets.

Every release is listed on the
[Releases page](https://github.com/danielyaa5/beckon/releases). Read the
"Unofficial" note below before you sign in.

## First launch (0.6.0)

**Find your AirTags** in the menu bar and **AirTags** in the sidebar open the
Items tab in Apple's Find My app (see "AirTags" below).

A short walkthrough covers signing in, starring favorites, adding the Ring and
Last rings desktop widgets, keyboard shortcuts, and opening AirTags in Find My. Skip it
at any time or reopen it from Settings > Show walkthrough. Signed-out users get
a compact sign-in card without the device sidebar. The widget extension carries
its own copy of Beckon's icon for the widget gallery.

## Device list

List view is the default, and Beckon remembers your layout choice.

Beckon checks Apple's reported device availability in the background while the
menu-bar app is running, targeting one request per second without overlapping requests. It
reuses its signed-in session and backs off after errors. This is Apple's reported
status, not a direct test of the device. No location or battery data is saved.

Ring is enabled for a device recently reported online. Offline devices are
muted and their immediate Ring action is disabled. Unknown status, failed checks,
and readings older than 15 seconds show **Needs refresh**. Use **Refresh status**
in the app or the refresh arrow in either widget. Widget updates are scheduled
by macOS; one-second polling does not guarantee one-second widget redraws.
Every Ring action checks availability again before sending. If the app is closed,
the widget can still refresh and send requests independently.

**Request sent** means the request completed without a detected rejection, not
that the device played a sound. **Couldn't confirm** means it may have gone
through; Beckon does not automatically retry that request. Open **Find My** to
request a sound for an offline device when it reconnects.

## Updates (0.5.1)

Beckon uses [Sparkle](https://sparkle-project.org/) to check for signed updates.
Choose **Check for Updates…** in the menu bar or Settings. Automatic checks can
be disabled in Settings; installing an update requires the user's confirmation.
Users on 0.4.4 or earlier must download and install 0.5.1 once.

For a release, run `release/notarize.sh VERSION`, then
`bash release/make-appcast.sh VERSION`. Sparkle 2.10.0's tools must be extracted
into `.tools/sparkle`; the signing key lives in the login Keychain under the
account `beckon`. Only its public key belongs in source control. Review the
resulting `release/build/VERSION/feed/appcast.xml`, upload `Beckon.zip` and
`Beckon.dmg` to the matching `vVERSION` GitHub release, then copy the feed to
`docs/appcast.xml` and publish the site. Do not publish the feed before its ZIP
exists. Increment both version fields in `project.yml` for every release.
The DMG contains the stapled notarized app; the ZIP is the signed update payload.

## Screenshots

| | |
|---|---|
| ![The window, listing devices with Ring buttons](docs/screenshot-window.png) | ![The menu bar popover with favorites and recent rings](docs/screenshot-menu.png) |
| ![The ring palette](docs/screenshot-palette.png) | ![The Ring and Last rings widgets](docs/screenshot-widgets.png) |

The demo and screenshots show made-up devices. They're drawn by Beckon's own
screenshot mode, so they match the app: `release/screenshots.sh` rebuilds all
of them (see "Screenshots and the website" below).

## What it does (0.4.0: ringing only)

- **Menu bar** (design 3, "keyboard-first"): search on top (⌘K), favorites with
  ⌘1–⌘9, the last rings with "Again", and the global shortcut key.
- **Ring palette**: a Spotlight-style panel on a global shortcut (⌃⌥Space by
  default). Type a few letters, press Return; ⌘↩ rings and keeps it open, ⌘S stars.
- **Ring shortcut key** (⌃⌥⌘R by default) rings your chosen device or first
  favorite from anywhere, with a "Ringing…" confirmation on screen. Both keys
  are changed in Settings (KeyboardShortcuts, no Accessibility needed).
- **App window** (design 5's layout): a sidebar of device groups, device cards
  to ring and star, hidden devices, ring history and Settings, plus an AirTags
  entry that opens Find My's Items tab. Like NordVPN, the app lives only in the menu bar
  with no Dock icon; the window brings a Dock icon while it's open (or always,
  if Settings says so).
- **Widgets**: "Ring" (favorites; small = one device with its shortcut key) and
  "Last rings" (tap to ring again). After a tap the
  button says "Sending…" while the widget signs in and sends the ring, then
  "Request sent" for 10 seconds or "Couldn't send" / "Couldn't confirm" for 30 (0.4.2; "Sending…"
  since 0.4.4). macOS doesn't redraw a widget while its button's intent is
  running ("Reload not permitted" in chronod's log), and the sign-in plus
  the ring take about 2.5 s, so `RingDeviceIntent.perform()` only marks
  "Sending…" and returns, and the ring finishes in a detached task
  (`WidgetRing`) that marks "Sent" or "Didn't ring". The status
  lives in `widget-status.json` in the App Group, written only by
  `RingDeviceIntent`; the timeline holds a second entry that clears it, so the
  button goes back to "Ring" without the extension running again. Don't add
  `invalidatableContent()` to the button labels: in 0.4.2 it made macOS treat
  clicks on the button as clicks on the widget's background ("Launching from
  widgetURL" in the log), which opened the app instead of ringing (0.4.3).
- **Shortcuts, Spotlight and Siri**: "Ring a Device", with
  phrases like "Ring Moreno 18 Pro with Beckon".
- **Links**: `beckon://ring/<name>`, `beckon://palette`, `beckon://open`
  (`beckon://airtags` opens Find My's Items tab), for
  Raycast, Alfred, Stream Deck or a bookmark. Links from before the rename
  (`findmyring://…`) still work.
- **Hide devices** you never ring (old Macs) from the menu, palette and widgets.
- **Ringing and availability**: device names and models load at sign-in or
  Reload list. Background checks retain only availability and its check time.
  No battery, location or place data is saved or displayed. Working sessions
  are reused rather than password-signing-in on every check.

Apple has no public API or Shortcuts action for Find My "Play Sound." The one
thing it does allow is signing in to Find My's web endpoints with your Apple
Account **password alone, no 2FA code** (the same thing `icloud.com/find`'s quick
access does). This app does exactly that, in pure Swift, and rings the device.

> Unofficial. It talks to Apple's private Find My web endpoints, so it can break
> whenever Apple changes them, and it is against iCloud's terms to automate the
> service. Fine for your own use / sharing the source; **not** App Store material
> (see `NOTES.md` / the GPT review — guideline 5.2.2 is the blocker).

## How it works

```
widget/menu tap → RingDeviceIntent → FindMyRingKit.FindMyRing
   → password-only SRP-6a sign-in to idmsa.apple.com  (pause 2FA)
   → accountLogin at setup.icloud.com  → findme web service
   → initClient (list devices) / playSound (ring)
```

No session or cookie is ever written to disk (the networking uses an ephemeral
`URLSession`). The app keeps one signed-in client in memory for up to 10
minutes (`App/FindMyService.swift`), so a reload followed by a ring signs in
once; the widget signs in fresh for each tap. What is stored: the password, in
the data protection Keychain in a shared access group, and the Apple Account
email, device list (names and models only), favorites, hidden
devices and settings in `config.json`, plus the last 200 rings in
`history.json`, both in the App Group container so the widgets can read them.
Apple emails you a confirmation after every ring.

## AirTags

Beckon doesn't ring AirTags. Apple's web Find My, which Beckon uses, has no
items at all, and an AirTag has no internet connection: only the Find My app
plays its sound, over Bluetooth. **Find your AirTags** in the menu, **AirTags**
in the window's sidebar and `beckon://airtags` open Find My's Items tab, where
you pick the AirTag and press Play Sound.

Versions up to 0.7.0 rang AirTags by driving the Find My app with
Accessibility, Screen Recording and text recognition; that code is gone, along
with Beckon's need for those two permissions. AirTag names, favorites and
rings that those versions saved are ignored and dropped at the next save. You
can switch Beckon off again under System Settings › Privacy & Security ›
Accessibility and Screen Recording.

## Layout

| Path | What |
|---|---|
| `Sources/FindMyRingKit/` | the shared, platform-agnostic kit: `SRP.swift` (the GSA SRP-6a port, verified against the Python `srp` library), `FindMyRing.swift` (sign-in + Find My calls), `Keychain.swift`, `Crypto.swift`, `Models.swift` |
| `Sources/ringcli/` | a command-line tool to test the kit against a real account |
| `Tests/` | SRP cross-check vectors (Python `srp` → Swift must match) |
| `App/` | the macOS app: `MenuPopover` (menu bar), `RingPalette` + `RingHUD` (palette, on-screen confirmation), `MainWindow` + `MainWindowController` (window, Dock behavior, links), `AppModel`, `FindMyService` (iCloud session), `Hotkeys`, `AppIntents` (Shortcuts/Siri); `Screenshots.swift` is the `--screenshots` mode |
| `release/notarize.sh` | Developer ID archive → notarize → staple → zip (signing via Xcode's account) |
| `release/screenshots.sh`, `release/make_media.py` | rebuild the README and website images and demo |
| `docs/` | the GitHub Pages site and the README images |
| `Widget/` | the WidgetKit extension: the Ring and Last rings widgets' timelines; buttons ring through `RingDeviceIntent` in the widget's own process |
| `Shared/` | `SharedStore` (App Group files + shared Keychain, and the screenshot demo data hook), `DeviceInfo` (device kinds, ring targets, status texts), `Theme`, `WidgetViews` (the widgets' views; the app draws them only for screenshots, and `WIDGET_EXTENSION` keeps the ring intent in the extension); compiled into both the app and the widget |
| `project.yml` | XcodeGen spec; `.xcodeproj` is generated, not committed |

`FindMyRingKit` is a SwiftPM package (depends only on `attaswift/BigInt` for the
2048-bit modular exponentiation). The app/widget are an Xcode project generated
from `project.yml`.

## Screenshots and the website

`release/screenshots.sh` builds a throwaway copy of the app (its widget and
Siri metadata stripped, so macOS never mistakes it for the installed one) and
runs `Beckon --screenshots <folder>`. That mode (`App/Screenshots.swift`)
swaps in made-up devices through `SharedStore.demo`, so nothing real is read,
written or rung, and saves each screen with `screencapture -l`: the windows sit
just above the wallpaper, behind everything else, because macOS won't capture
a window placed off screen. The widgets' views live in
`Shared/WidgetViews.swift` so the app can draw them too. Then
`release/make_media.py` (Pillow and ffmpeg) composes the screenshots, the
widgets picture and the demo GIF/MP4 into `docs/`.

`docs/` is also the GitHub Pages site, https://danielyaa5.github.io/beckon/
(`docs/index.html`; `.nojekyll` serves files as they are).

## Build

```bash
# the kit + CLI (and SRP tests)
swift build
swift test

# test the sign-in against a real account (prompts for the password, hidden)
.build/debug/ringcli list <appleID>
.build/debug/ringcli ring <appleID> "<device name>"

# the app + widget
.tools/xcodegen/bin/xcodegen generate
xcodebuild -project FindMyRing.xcodeproj -scheme FindMyRing -configuration Debug \
  -derivedDataPath build/dd -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
open "build/dd/Build/Products/Debug/Beckon.app"
```

XcodeGen is vendored under `.tools/` (portable binary, no Homebrew). Signing uses
the Apple Development cert for team `4JWVY7832S`; the App Group and shared
Keychain group are registered automatically by `-allowProvisioningUpdates`.

## Status (2026-10-16)

- ✅ Pure-Swift password-only Find My sign-in, verified against the real account.
- ✅ SRP port cross-checked against the Python `srp` library (`s2k` + `s2k_fo`).
- ✅ macOS menu-bar app: sign in once, ring any device.
- ✅ macOS widget: interactive buttons for your **starred devices only** (0.2.4;
  up to 3 in the small size, 6 in the medium), which ring from the widget
  process (shared Keychain + App Group), so it works with the app closed. **The widget extension
  must be App-Sandboxed** (`com.apple.security.app-sandbox` + `network.client`
  in `Widget/RingWidget.entitlements`): macOS silently never registers an
  unsandboxed widget — no log line, no gallery entry. The app itself stays
  unsandboxed.
- ✅ Sharing between the app (unsandboxed) and the widget (sandboxed), after the
  widget kept saying "sign in" and the app forgot its sign-in on relaunch:
  - the password must be in the **data protection keychain**
    (`kSecUseDataProtectionKeychain`); in macOS's legacy login keychain
    `kSecAttrAccessGroup` is ignored, so the widget can't read it (0.2.1).
    Every Keychain query must carry that flag: on macOS a query without it
    can hit both keychains, and 0.2.2's "delete the old login-keychain copy"
    deleted the shared password too (fixed in 0.2.3 by dropping all
    login-keychain code);
  - the rest lives in one JSON file in the App Group container, and on macOS
    the App Group must be **team-prefixed** (`4JWVY7832S.com.danielyakobian.findmy-ring`,
    `$(TeamIdentifierPrefix)…` in the entitlements), not `group.…` (0.2.2).
    Since macOS 15 a `group.` container is only open to an app whose
    provisioning profile lists the group; the Developer ID profiles Xcode made
    don't, so macOS denied every read and write, silently (the log shows
    `tccd` refusing `kTCCServiceSystemPolicyAppDataDetailed` with authReason 5).
    A team-prefixed group needs no profile entry. iOS needs `group.` IDs, so
    `SharedStore.appGroup` differs per platform.
  - At launch the app takes the Apple Account from the saved password item if
    the settings file names none, loads the device list if none is saved, and
    calls `WidgetCenter.reloadAllTimelines()` then and whenever sign-in,
    devices or favorites change.
  - Both processes log to subsystem `com.danielyakobian.findmy-ring`:
    `log show --last 10m --predicate 'subsystem == "com.danielyakobian.findmy-ring"'`.
- ✅ Sign-in (0.3.2): the password is checked with Apple before it is saved, so
  a typo never shows as "Signed in"; and when Apple rejects the saved password
  (changed, or the account locked) the app forgets it, so the hourly refresh and
  menu opens never retry a bad password (repeated rejected sign-ins are what get
  an Apple Account locked). The kit (0.3.3) only calls a failure "wrong
  password" on HTTP 401 or Apple's -20101 code; 409, 412, 429 and 5xx get
  their own messages (Apple answers a malformed account name with a 503, which
  0.3.2 still read as a wrong password).
- ✅ App icon (0.3.2): `Icon/AppIcon.icon`, an Icon Composer document (layered
  SVGs + `icon.json`, so macOS draws it in Liquid Glass with light, dark and
  tinted versions). XcodeGen 2.43 doesn't know `.icon`, so `project.yml` maps
  the extension to a single resource file (`options.fileTypes.icon`) and sets
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`; actool then writes the layers
  to `Assets.car` and an `AppIcon.icns` for older macOS. Preview a change with
  Icon Composer's `ictool <file.icon> --export-image --platform macOS
  --rendition Default --width 512 --height 512 --scale 1 --output-file x.png`.
- ✅ Developer ID signed + notarized via `release/notarize.sh` (0.1.0 to 0.4.4).
- ✅ Favorites: star devices to pin them at the top of the menu; starred
  devices are also what the widget shows.
- ✅ Layout and robustness (0.3.4–0.3.6), checked with window captures
  (`screencapture -x -o -l <CGWindowID>`; find IDs with
  `CGWindowListCopyWindowInfo`):
  - The window keeps its own size: by default `NSHostingController` sized it
    to the content's ideal size (860×1838, taller than the screen), so
    `MainWindowController` sets `sizingOptions = []`, opens at 1060×720,
    autosaves as "FindMyRingWindow" and keeps a restored frame on screen.
  - Desktop widgets are drawn dimmed (vibrant) while another app is in
    front; white labels on the orange fill vanished there, so filled buttons
    and map pins use `filledFace(_:)` (primary on a light tint outside full
    color).
  - The palette ignores its hidden title bar's safe area (no empty band).
  - Offline devices sort after online ones in the menu, palette and window.
  - A device-list reply without `content` is an error, and an empty list never
    replaces a saved one; automatic reloads pause 30 minutes after a server or
    network error; `history.json` writes are
    coordinated (`NSFileCoordinator`) between the app and the widget.
- ✅ Renamed Beckon (0.4.1): the app's name, menu and window texts, Siri
  phrases, widget titles and links (`beckon://`). Everything that identifies
  the app to macOS stays as it was — bundle id `com.danielyakobian.findmy-ring`,
  the App Group and Keychain group, the log subsystem, the widget kinds — so
  the saved sign-in, favorites, permissions and widgets already on the desktop
  carry over. The repo folder, the Xcode project and scheme (`FindMyRing`) and
  the kit (`FindMyRingKit`) keep the old name.
- ⬜ iOS app + widget target (same kit; a personal build for the owner first).

**Testing a build:** install only the notarized app in `/Applications`. Leftover
copies of `Beckon.app` (or, before 0.4.1, `Find My Ring.app`) (DerivedData, `.xcarchive`, `notarized/`) all claim
the same bundle id and confuse LaunchServices/PlugInKit about which one owns the
widget; `release/notarize.sh` builds into `release/build/<ver>/dd`, so delete
that folder, the archive and `notarized/` after installing (keep the zip).
When the app's path changes (as with the 0.4.1 rename), macOS's widget host
can keep launching the widget from the old path ("Missing executable detected"
in the log; the widget keeps its old look and taps fail): `killall chronod`
fixes it, and launchd starts it again at once.
If a desktop widget then shows only a sliver on screen while screenshots show
it whole, `killall NotificationCenter` makes the desktop redraw it.

There is also a separate, already-running home-network version in
a separate legacy Find My server used by Shortcuts widgets;
this project is the standalone, no-server app that replaces it.
