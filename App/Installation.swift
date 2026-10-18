import AppKit

@MainActor
enum Installation {
    static func finishIfInstalled() -> Bool {
        let app = Bundle.main.bundleURL.standardizedFileURL
        let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        guard applications.contains(where: { app.deletingLastPathComponent() == $0.standardizedFileURL }) else {
            let alert = NSAlert()
            alert.messageText = "Move Beckon to Applications"
            alert.informativeText = "Drag Beckon into the Applications folder, then open it there to finish installing. This also lets Beckon install future updates."
            alert.addButton(withTitle: "Show in Finder and Quit")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([app])
            }
            return false
        }
        // Only eject our read-only installer, after its matching installed copy
        // is running. Never force an eject (Finder may still be copying).
        let volume = URL(fileURLWithPath: "/Volumes/Beckon Installer", isDirectory: true)
        guard let values = try? volume.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
              values.volumeIsReadOnly == true,
              let build = try? String(contentsOf: volume.appendingPathComponent(".beckon-installer"), encoding: .utf8),
              build == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return true }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        return true
    }
}
