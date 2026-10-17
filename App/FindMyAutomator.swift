import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import os

/// Rings an AirTag by driving the Mac's Find My app. AirTags can't be rung
/// through iCloud (Apple's web Find My doesn't support items), so the only way
/// is the app itself, which reaches the AirTag over Bluetooth — it works only
/// when the AirTag is within Bluetooth range of this Mac.
///
/// Find My on macOS 26+ exposes its menus to Accessibility but not its window
/// contents, so the window is read by screen capture + text recognition and
/// pressed with synthesized clicks. The sequence and its constants are ported
/// from findmy-cli's `ring` command (MIT, Omar Shahine,
/// github.com/omarshahine/findmy-cli), adapted for Items.
///
/// Needs Accessibility (menu press + clicks) and Screen Recording (capture),
/// and an awake, unlocked display.
@MainActor
final class FindMyAutomator {

    struct AutomationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct OCRLine {
        let text: String
        let rect: CGRect   // image pixels, top-left origin
    }

    struct Shot {
        let lines: [OCRLine]
        let scale: CGFloat      // image pixels per window point
        let sidebarPx: CGFloat  // sidebar's right edge, in image pixels
    }

    /// The Items list's bounds in a capture, in image pixels.
    struct SidebarLayout {
        let rightPx: CGFloat    // sidebar's right edge
        let rowTopPx: CGFloat   // rows start below the People / Devices / Items pills
    }

    private nonisolated static let log = Logger(subsystem: "com.danielyakobian.findmy-ring", category: "airtags")

    static let bundleID = "com.apple.findmy"
    /// Width of Find My's floating sidebar, in points, on macOS 26+.
    static let sidebarPoints: CGFloat = 340
    static let captureScale: CGFloat = 2

    /// "Play Sound" in the languages Find My ships (from findmy-cli). The button
    /// has no readable identifier, so its label is the only handle.
    nonisolated static let playSoundLabels: [String] = [
        "play sound", "émettre un son", "emettre un son", "ton abspielen",
        "sound abspielen", "reproducir sonido", "riproduci suono", "emitir som",
        "geluid afspelen", "spela upp ljud", "afspil lyd", "spill av lyd",
        "toista ääni", "odtwórz dźwięk", "přehrát zvuk", "hang lejátszása",
        "ses çal", "воспроизвести звук", "サウンドを再生", "사운드 재생",
        "播放声音", "播放聲音", "เล่นเสียง", "phát âm thanh",
    ].map(FindMyAutomator.normalize)

    // MARK: Permissions

    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        // The value of kAXTrustedCheckOptionPrompt (a C global Swift 6 won't touch).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    // MARK: Ring

    /// Scans and rings both drive Find My's one window, so they must never
    /// overlap (a scan scrolling the list under a ring's click would ring the
    /// wrong row).
    private var working = false

    private func beginWork() throws {
        guard !working else {
            throw AutomationError(message: "Beckon is already using Find My. Try again in a moment.")
        }
        working = true
    }

    private func requirePermissions() throws {
        guard Self.hasAccessibility else {
            throw AutomationError(message: "AirTags need Accessibility access for Beckon.")
        }
        guard Self.hasScreenRecording else {
            throw AutomationError(message: "AirTags need Screen Recording access for Beckon.")
        }
    }

    /// Rings one item. `otherNames` are the other known items, so a near
    /// OCR match is never taken for a different item ("Bag 1" vs "Bag 2").
    func ring(itemName: String, otherNames: [String] = []) async throws {
        try requirePermissions()
        try beginWork()
        defer { working = false }

        let cursorBefore = CGEvent(source: nil)?.location
        let app = try await launchFindMy()
        defer {
            // Hand the screen back: hide Find My (macOS reactivates the app you
            // were in) and put the pointer where it was.
            app.hide()
            if let cursorBefore { CGWarpMouseCursorPosition(cursorBefore) }
        }

        pressMenuItem(of: app, identifier: "items")
        try await pause(0.8)
        // Catalyst only routes synthetic clicks to the frontmost app.
        NSApp.yieldActivation(to: app)
        app.activate()
        try await pause(0.5)

        var window = try await findMyWindow()
        let others = otherNames.filter { Self.normalize($0) != Self.normalize(itemName) }

        // Fast path: this item's card is already open.
        let first = try await capture(window)
        if let button = Self.playSoundButton(in: first.lines),
           Self.card(first.lines, shows: itemName, above: button, others: others) {
            Self.log.notice("Ring: card already open")
            try await pressPlaySound(button, in: first, window: window)
            return
        }

        // Find the row and open it (findRow waits for the list to stop moving:
        // a click on a list that is still gliding only stops it).
        let row = try await findRow(named: itemName, others: others, window: window)
        Self.log.notice("Ring: row found at \(Int(row.x - window.frame.minX), privacy: .public),\(Int(row.y - window.frame.minY), privacy: .public) in a \(Int(window.frame.width), privacy: .public)x\(Int(window.frame.height), privacy: .public) window")
        try await click(row)
        try await pause(1.5)
        window = try await findMyWindow()

        // macOS 27 expands the clicked row in place, with Directions and a
        // short "Play" button under it; older Find My hangs a card off the map
        // pin. Look for the button first.
        if let found = try await pollForPlaySound(window: window, timeout: 3.0) {
            try await ringFromCard(found, itemName: itemName, others: others, window: window)
            return
        }
        var afterRow = try await capture(window)
        if Self.inlineCardShown(afterRow.lines, sidebarPx: afterRow.sidebarPx) {
            // The expanded row's buttons can sit below the window's edge.
            let sidebar = CGPoint(x: window.frame.minX + Self.sidebarPoints / 2, y: window.frame.midY)
            for _ in 0..<2 {
                try await scroll(at: sidebar, dy: -3)
                try await pause(0.8)
                if let found = try await pollForPlaySound(window: window, timeout: 1.5) {
                    try await ringFromCard(found, itemName: itemName, others: others, window: window)
                    return
                }
            }
            afterRow = try await capture(window)
            dump(afterRow, as: "ring-inline-card-no-play")
            throw AutomationError(message: "Find My showed “\(itemName)” but no Play button, so nothing was rung.")
        }
        dump(afterRow, as: "ring-after-row-click")
        Self.log.notice("Ring: no card after the row click (\(afterRow.lines.count, privacy: .public) OCR lines), trying the map pin")

        let mapCenter = CGPoint(
            x: window.frame.minX + Self.sidebarPoints + (window.frame.width - Self.sidebarPoints) / 2,
            y: window.frame.midY
        )
        // Find My drops clicks while the map is still animating, hence the
        // retry ladder with growing delays.
        var lastShot = afterRow
        for attempt in 0..<4 {
            try await click(mapCenter)
            try await pause(1.0 + Double(attempt) * 0.2)
            try await click(mapCenter)
            if let found = try await pollForPlaySound(window: window, timeout: 2.0 + Double(attempt) * 0.5) {
                try await ringFromCard(found, itemName: itemName, others: others, window: window)
                return
            }
            lastShot = try await capture(window)
            Self.log.notice("Ring: pin attempt \(attempt, privacy: .public), no Play Sound yet (\(lastShot.lines.count, privacy: .public) OCR lines)")
        }
        dump(lastShot, as: "ring-no-play-sound")
        throw AutomationError(message: "No Play Sound for “\(itemName)”. It's probably out of Bluetooth range of this Mac.")
    }

    private func ringFromCard(_ found: (button: OCRLine, shot: Shot), itemName: String,
                              others: [String], window: SCWindow) async throws {
        guard Self.card(found.shot.lines, shows: itemName, above: found.button, others: others) else {
            Self.log.error("Ring: Play Sound at \(Int(found.button.rect.minX), privacy: .public),\(Int(found.button.rect.minY), privacy: .public) px, but the card above it isn't this item's")
            dump(found.shot, as: "ring-wrong-card")
            throw AutomationError(message: "Find My opened a card that isn't “\(itemName)”, so nothing was rung.")
        }
        Self.log.notice("Ring: Play Sound at \(Int(found.button.rect.minX), privacy: .public),\(Int(found.button.rect.minY), privacy: .public) px, clicking")
        try await pressPlaySound(found.button, in: found.shot, window: window)
    }

    /// Clicks Play Sound and checks Find My took it: its label changes or a
    /// "Stop Sound" / "Playing" / "Pending" state appears. Tries the label,
    /// then the icon above it (the button's shape differs between Find My
    /// versions), and never clicks twice once anything near it has changed.
    private func pressPlaySound(_ button: OCRLine, in shot: Shot, window: SCWindow) async throws {
        let x = window.frame.minX + button.rect.midX / shot.scale
        let points = [
            CGPoint(x: x, y: window.frame.minY + button.rect.midY / shot.scale),
            CGPoint(x: x, y: window.frame.minY + button.rect.minY / shot.scale - 10),
        ]
        let before = Self.textNear(button, in: shot.lines)
        for (i, point) in points.enumerated() {
            try await click(point)
            try await pause(1.2)
            let after = try await capture(window)
            if Self.soundAcknowledged(after.lines) || Self.textNear(button, in: after.lines) != before {
                Self.log.notice("Ring: Find My took the Play Sound click (\(i == 0 ? "label" : "icon", privacy: .public))")
                return
            }
        }
        dump(try await capture(window), as: "ring-play-sound-ignored")
        throw AutomationError(message: "Find My didn't respond to Play Sound, so nothing was rung. Try it in Find My.")
    }

    // MARK: List items

    /// Every name in Find My's Items list (AirTags and other Find My network
    /// items), read from the top a page at a time, in list order. findmy-cli's
    /// `items` reads one screenful; this scrolls, so long lists come out whole.
    func listItems() async throws -> [String] {
        try requirePermissions()
        try beginWork()
        defer { working = false }

        let cursorBefore = CGEvent(source: nil)?.location
        let app = try await launchFindMy()
        defer {
            app.hide()
            if let cursorBefore { CGWarpMouseCursorPosition(cursorBefore) }
        }

        pressMenuItem(of: app, identifier: "items")
        try await pause(0.8)
        NSApp.yieldActivation(to: app)
        app.activate()
        try await pause(0.5)

        let window = try await findMyWindow()
        let sidebar = CGPoint(x: window.frame.minX + Self.sidebarPoints / 2, y: window.frame.midY)
        for _ in 0..<20 { try await scroll(at: sidebar, dy: 10) }
        try await pause(0.5)

        var names: [String] = []
        var layout: SidebarLayout?
        var lastPage = ""
        var firstShot: Shot?
        defer { if names.isEmpty, let firstShot { dump(firstShot, as: "items-scan-empty") } }
        for page in 0..<30 {
            let shot = try await capture(window)
            if firstShot == nil { firstShot = shot }
            if layout == nil {
                layout = Self.sidebarLayout(in: shot.lines, fallbackRightPx: shot.sidebarPx)
                guard layout != nil else {
                    Self.log.error("Items scan: no People/Devices/Items pills in \(shot.lines.count, privacy: .public) OCR lines")
                    throw AutomationError(message: "Find My's sidebar isn't showing. Show it (View ▸ Show Sidebar), then try again.")
                }
            }
            guard let layout else { break }
            let onPage = Self.itemNames(in: shot.lines, layout: layout, scale: shot.scale)
            for name in onPage where !names.contains(where: { Self.normalize($0) == Self.normalize(name) }) {
                names.append(name)
            }
            Self.log.notice("Items scan page \(page, privacy: .public): \(shot.lines.count, privacy: .public) OCR lines, \(onPage.count, privacy: .public) names, \(names.count, privacy: .public) so far")

            let text = shot.lines.filter { $0.rect.midX < layout.rightPx }.map { Self.normalize($0.text) }.joined(separator: "|")
            if text == lastPage { break }   // the list stopped moving: bottom reached
            lastPage = text
            try await scroll(at: sidebar, dy: -5)
            try await pause(0.4)
        }
        return names
    }

    // MARK: Find My app

    private func launchFindMy() async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            running.unhide()
            NSApp.yieldActivation(to: running)
            running.activate()
            try await pause(0.6)
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw AutomationError(message: "Couldn't find the Find My app on this Mac.")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        try await pause(2.5)   // let its window appear
        return app
    }

    /// Presses a menu item by its accessibility identifier (View ▸ People /
    /// Devices / Items are "people" / "devices" / "items").
    private func pressMenuItem(of app: NSRunningApplication, identifier: String) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = Self.element(ax, kAXMenuBarAttribute),
              let item = Self.findMenuItem(in: bar, identifier: identifier) else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    private func findMyWindow() async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Self.bundleID
                && $0.windowLayer == 0 && $0.frame.width > 500 && $0.frame.height > 300
        }
        guard let window = candidates.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else {
            throw AutomationError(message: "Couldn't see Find My's window. Make sure the Mac is awake and unlocked.")
        }
        return window
    }

    // MARK: Screen reading

    private func capture(_ window: SCWindow) async throws -> Shot {
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * Self.captureScale)
        config.height = Int(window.frame.height * Self.captureScale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: config
        )
        // Text recognition takes a moment per capture; keep it off the main
        // thread so the menu, palette and shortcut keys stay responsive.
        let lines = await Task.detached(priority: .userInitiated) { Self.recognizeText(in: image) }.value
        return Shot(lines: lines, scale: Self.captureScale, sidebarPx: Self.sidebarPoints * Self.captureScale)
    }

    /// Saves what a capture read (positions in image pixels, then the text) to
    /// ~/Library/Logs/Beckon/<name>.txt, so a failed ring or scan can be
    /// worked out afterwards from Find My's actual layout. Off unless switched
    /// on, because it holds item names and places:
    /// `defaults write com.danielyakobian.findmy-ring AirTagDiagnostics -bool YES`
    private func dump(_ shot: Shot, as name: String) {
        guard UserDefaults.standard.bool(forKey: "AirTagDiagnostics") else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Beckon", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = shot.lines
            .sorted { $0.rect.minY < $1.rect.minY }
            .map { line in
                let r = line.rect
                return "\(Int(r.minX)),\(Int(r.minY)) to \(Int(r.maxX)),\(Int(r.maxY))  \(line.text)"
            }
            .joined(separator: "\n")
        try? text.write(to: folder.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        Self.log.notice("Saved what Find My showed to Logs/Beckon/\(name, privacy: .public).txt")
    }

    nonisolated static func recognizeText(in image: CGImage) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox   // normalized, bottom-left origin
            return OCRLine(
                text: text,
                rect: CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
            )
        }
    }

    /// Scrolls the sidebar to the top, then down a page at a time, until a row
    /// matches the name: exactly, or one character off when no other known
    /// item is as close. Then waits for the list to stop moving and returns
    /// where the row is now.
    private func findRow(named name: String, others: [String], window: SCWindow) async throws -> CGPoint {
        let sidebar = CGPoint(x: window.frame.minX + Self.sidebarPoints / 2, y: window.frame.midY)
        for _ in 0..<20 { try await scroll(at: sidebar, dy: 10) }
        try await pause(0.5)

        func match(in shot: Shot) -> OCRLine? {
            Self.bestRow(in: shot.lines.filter { $0.rect.midX < shot.sidebarPx }, name: name, others: others)
        }
        var lastPage = ""
        for _ in 0..<20 {
            let shot = try await capture(window)
            if var line = match(in: shot) {
                for _ in 0..<6 {
                    try await pause(0.3)
                    guard let again = match(in: try await capture(window)) else { break }
                    let settled = abs(again.rect.midY - line.rect.midY) < 3
                    line = again
                    if settled { break }
                }
                return CGPoint(
                    x: window.frame.minX + line.rect.midX / shot.scale,
                    y: window.frame.minY + line.rect.midY / shot.scale
                )
            }
            let page = shot.lines.filter { $0.rect.midX < shot.sidebarPx }.map { Self.normalize($0.text) }.joined(separator: "|")
            if page == lastPage { break }   // the list stopped moving: bottom reached
            lastPage = page
            try await scroll(at: sidebar, dy: -5)
            try await pause(0.6)
        }
        throw AutomationError(message: "Couldn't find “\(name)” in Find My's Items list. Check the name matches Find My exactly, and that the sidebar is showing.")
    }

    /// The line naming this item: an exact match, else the one near match
    /// that no other known item explains better.
    nonisolated static func bestRow(in lines: [OCRLine], name: String, others: [String]) -> OCRLine? {
        let target = normalize(name)
        if let exact = lines.first(where: { normalize($0.text) == target }) { return exact }
        let near = lines.filter { nearMatch($0.text, name, others: others) }
        return near.count == 1 ? near[0] : nil
    }

    private func pollForPlaySound(window: SCWindow, timeout: Double) async throws -> (button: OCRLine, shot: Shot)? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let shot = try await capture(window)
            if let button = Self.playSoundButton(in: shot.lines) { return (button, shot) }
            if Date() > deadline { return nil }
            try await pause(0.3)
        }
    }

    nonisolated static func playSoundButton(in lines: [OCRLine]) -> OCRLine? {
        lines.first { line in
            let text = normalize(line.text)
            guard !text.isEmpty else { return false }
            if playSoundLabels.contains(where: { text.contains($0) }) { return true }
            // macOS 27's compact button: a speaker icon (OCR'd as "1›)" or
            // similar) and the single word "Play".
            let words = text.split(separator: " ")
            return words.last == "play" && words.count <= 2
        }
    }

    /// macOS 27's expanded row: a "Directions" button in the sidebar.
    nonisolated static func inlineCardShown(_ lines: [OCRLine], sidebarPx: CGFloat) -> Bool {
        lines.contains { $0.rect.midX < sidebarPx && normalize($0.text).hasSuffix("directions") }
    }

    /// Whether the card holding this Play button is this item's: of the known
    /// item names above the button in the same column (within a card's
    /// height), the nearest one must be this item, matched exactly or one
    /// character off when no other known item is as close. On macOS 27 the
    /// card is the clicked row expanded in the list, so other items' rows sit
    /// just above it; map labels and those rows never qualify.
    nonisolated static func card(_ lines: [OCRLine], shows name: String, above button: OCRLine,
                                 others: [String]) -> Bool {
        func isThis(_ text: String) -> Bool {
            normalize(text) == normalize(name) || nearMatch(text, name, others: others)
        }
        func isKnownItem(_ text: String) -> Bool {
            isThis(text) || others.contains { normalize($0) == normalize(text) || sameName(text, $0) }
        }
        let nearest = lines
            .filter { line in
                line.rect.maxY <= button.rect.minY + 4
                    && button.rect.minY - line.rect.maxY < 900
                    && abs(line.rect.midX - button.rect.midX) < 520
                    && isKnownItem(line.text)
            }
            .max { $0.rect.maxY < $1.rect.maxY }
        return nearest.map { isThis($0.text) } ?? false
    }

    /// One character off from this name, and closer to it than to any other
    /// known item's name.
    nonisolated static func nearMatch(_ text: String, _ name: String, others: [String]) -> Bool {
        guard sameName(text, name), normalize(text) != normalize(name) else { return false }
        let d = editDistance(normalize(text), normalize(name))
        return !others.contains { editDistance(normalize(text), normalize($0)) <= d }
    }

    /// The text within a few rows of a button, to tell whether a click changed it.
    nonisolated static func textNear(_ button: OCRLine, in lines: [OCRLine]) -> [String] {
        lines.filter { abs($0.rect.midY - button.rect.midY) < 300 && abs($0.rect.midX - button.rect.midX) < 600 }
            .sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
            .map { normalize($0.text) }
    }

    /// Find My's states after Play Sound (English).
    nonisolated static func soundAcknowledged(_ lines: [OCRLine]) -> Bool {
        lines.contains { line in
            let t = normalize(line.text)
            return t.contains("stop sound") || t.contains("playing") || t.contains("pending")
        }
    }

    /// OCR text naming this item: equal after normalizing, or, for names of
    /// five or more characters, one character off, since OCR can read the same
    /// label differently between captures ("GSX8R" / "GSXBR" in findmy-cli's
    /// alias list). Callers prefer an exact match and take a near one only
    /// when it is the only candidate.
    nonisolated static func sameName(_ text: String, _ name: String) -> Bool {
        let a = normalize(text), b = normalize(name)
        if a == b { return true }
        return b.count >= 5 && abs(a.count - b.count) <= 1 && editDistance(a, b) <= 1
    }

    nonisolated static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Items list parsing (rules ported from findmy-cli's ParseItems)

    /// Where the Items list sits, from the sidebar's People / Devices / Items
    /// pills. nil when they aren't on screen: the sidebar is hidden, and
    /// anything read would be map labels.
    nonisolated static func sidebarLayout(in lines: [OCRLine], fallbackRightPx: CGFloat) -> SidebarLayout? {
        let pills = lines.filter {
            tabLabels.contains(normalize($0.text)) && $0.rect.minY < 320 && $0.rect.midX < fallbackRightPx
        }
        guard Set(pills.map { normalize($0.text) }).count >= 2,
              let pillsRight = pills.map(\.rect.maxX).max(),
              let pillsBottom = pills.map(\.rect.maxY).max() else { return nil }
        return SidebarLayout(rightPx: min(fallbackRightPx, pillsRight + 40), rowTopPx: pillsBottom + 12)
    }

    /// The item names on one page. Each row is a name over a "<place> • <time>"
    /// line. A name counts only when that second line sits right under it, so
    /// a row cut off at the bottom is read on the next page, and a lone second
    /// line at the top (its name scrolled away) is skipped.
    nonisolated static func itemNames(in lines: [OCRLine], layout: SidebarLayout, scale: CGFloat) -> [String] {
        // Right of the item icons. On macOS 27 names start about 58 pt in, so
        // findmy-cli's 60 pt cut dropped most of them and every second line.
        let textMinX = 50 * scale
        let candidates = lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let key = normalize(text)
            return !key.isEmpty
                && line.rect.midX < layout.rightPx
                && line.rect.minY >= layout.rowTopPx
                && line.rect.minX >= textMinX
                && !skipLabels.contains(key) && !tabLabels.contains(key)
                && !isDistance(text) && !isBattery(text)
        }
        let rows = mergeWrapped(joinSameLine(candidates))

        var names: [String] = []
        var index = 0
        while index < rows.count {
            let line = rows[index]
            let text = line.text.trimmingCharacters(in: .whitespaces)
            // Its second line: the first line below it, close under it.
            let below = rows[(index + 1)...].first { $0.rect.minY > line.rect.midY }
            if !looksLikeSecondLine(text), let below, below.rect.minY - line.rect.maxY < line.rect.height {
                names.append(text)
                // Move past the name's line and its second line.
                index = rows[(index + 1)...].firstIndex { $0.rect.minY > below.rect.midY } ?? rows.count
            } else {
                index += 1
            }
        }
        return names
    }

    /// The sidebar's tab pills: People / Devices / Items in the 41 languages of
    /// findmy-cli's locale table, plus macOS 27's new "Me" (English only so far).
    nonisolated static let tabLabels: Set<String> = Set([
        "people", "devices", "items", "me",
        "apparaten", "appareils", "articole", "artículos", "aygıtlar", "barang", "dispositius",
        "dispositivi", "dispositivos", "dispozitive", "enheder", "enheter", "esineet", "eszközök",
        "föremål", "genstande", "geräte", "item", "itens", "kişiler", "käyttäjät", "laitteet", "lidé",
        "naprave", "nesneler", "người", "objecten", "objectes", "objekte", "objekter", "objetos",
        "objets", "oggetti", "orang", "osebe", "osobe", "osoby", "perangkat", "peranti", "persoane",
        "personas", "persone", "personen", "personer", "persones", "personnes", "pessoas", "predmeti",
        "predmety", "przedmioty", "předměty", "személyek", "thiết bị", "tárgyak", "uređaji",
        "urządzenia", "vật dụng", "zariadenia", "zařízení", "ľudia", "άτομα", "αντικείμενα",
        "συσκευές", "вещи", "люди", "пристрої", "речі", "устройства", "אנשים", "מכשירים", "פריטים",
        "الأجهزة", "الأشخاص", "الأغراض", "आइटम", "डिवाइस", "लोग", "ผู้คน", "สิ่งของ", "อุปกรณ์",
        "デバイスを探す", "人を探す", "持ち物を探す", "物品", "联系人", "聯絡人", "裝置", "设备", "기기",
        "물품", "사람",
    ].map(normalize))

    /// Sidebar text that is never an item: the tab pills, search, map controls
    /// and the list's own buttons.
    nonisolated static let skipLabels: Set<String> = [
        "people", "devices", "items", "me", "search", "facetime", "3d", "n",
        "identify found item", "add item", "add airtag", "add other item",
    ]

    /// The "<place> • <time>" line under a name, or one of its stand-ins.
    nonisolated static func looksLikeSecondLine(_ text: String) -> Bool {
        let key = normalize(text)
        return text.contains("•") || text.contains("·") || text.contains("∙")
            || ["with you", "no location found", "location not available", "address unavailable",
                "offline", "now"].contains(key)
            || key.hasSuffix(" ago")
    }

    nonisolated static func isDistance(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        return [" mi", " km", " ft", " m", " yd"].contains { lowered.hasSuffix($0) }
            && lowered.first?.isNumber == true
    }

    nonisolated static func isBattery(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.hasSuffix("%") else { return false }
        let digits = compact.dropLast()
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// Top-to-bottom, joining pieces OCR split off one label (side by side on
    /// the same line, close together).
    nonisolated static func joinSameLine(_ lines: [OCRLine]) -> [OCRLine] {
        let sorted = lines.sorted { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
        var out: [OCRLine] = []
        for line in sorted {
            if let last = out.last,
               abs(line.rect.midY - last.rect.midY) < min(line.rect.height, last.rect.height) / 2 {
                let (left, right) = last.rect.minX <= line.rect.minX ? (last, line) : (line, last)
                if right.rect.minX - left.rect.maxX < 2 * min(left.rect.height, right.rect.height) {
                    out[out.count - 1] = OCRLine(text: left.text + " " + right.text, rect: left.rect.union(right.rect))
                    continue
                }
            }
            out.append(line)
        }
        return out
    }

    /// Re-joins a long "City, ST • 2 min. ago" that OCR wrapped onto two lines.
    nonisolated static func mergeWrapped(_ lines: [OCRLine]) -> [OCRLine] {
        var out: [OCRLine] = []
        for line in lines {
            if let last = out.last, looksLikeSecondLine(last.text),
               line.rect.minY - last.rect.maxY < 12,
               normalize(line.text).hasSuffix("ago") {
                out[out.count - 1] = OCRLine(text: last.text + " " + line.text, rect: last.rect.union(line.rect))
            } else {
                out.append(line)
            }
        }
        return out
    }

    nonisolated static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let kept = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Synthesized input (same events as findmy-cli's helper)

    /// Synthesized input goes wherever the pointer is, so stop if the user
    /// switched apps mid-way rather than click into their browser or mail.
    private func requireFindMyInFront() throws {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID else {
            throw AutomationError(message: "Stopped because Find My left the front, so nothing was clicked. Try again.")
        }
    }

    private func click(_ point: CGPoint) async throws {
        try requireFindMyInFront()
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        try await pause(0.05)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        try await pause(0.04)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Catalyst ignores discrete scroll-wheel events, so send a phased,
    /// continuous (trackpad-style) gesture. Positive dy scrolls up.
    private func scroll(at point: CGPoint, dy: Int32) async throws {
        try requireFindMyInFront()
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        try await pause(0.1)
        let steps = 5
        let stepDy = Int32(Double(dy) * 30 / Double(steps))
        for i in 0..<steps {
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                wheel1: stepDy, wheel2: 0, wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (i == steps - 1 ? 4 : 2))
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event?.post(tap: .cghidEventTap)
            try await pause(0.02)
        }
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Accessibility helpers

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func findMenuItem(in element: AXUIElement, identifier: String, depth: Int = 0) -> AXUIElement? {
        if depth > 8 { return nil }
        var role: AnyObject?, ident: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &ident)
        if (role as? String) == kAXMenuItemRole, (ident as? String) == identifier { return element }
        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] {
            if let found = findMenuItem(in: child, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }
}
