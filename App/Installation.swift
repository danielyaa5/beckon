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
        return true
    }

    static func offerCleanup() async {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let identifier = Bundle.main.bundleIdentifier else { return }
        let disks = await Task.detached {
            matchingInstallers(build: build, identifier: identifier)
        }.value
        for disk in disks {
            let download = disk.download
            var removeDownload = false
            if let download {
                let alert = NSAlert()
                alert.messageText = "Beckon is installed"
                alert.informativeText = "Move \u{201c}\(download.lastPathComponent)\u{201d} from Downloads to Trash? Beckon will eject the installer disk. Your installed app stays in Applications."
                alert.addButton(withTitle: "Move Installer to Trash")
                alert.addButton(withTitle: "Keep Download")
                NSApp.activate(ignoringOtherApps: true)
                removeDownload = alert.runModal() == .alertFirstButtonReturn
            }
            do {
                // Never force an eject: Finder might still be copying files.
                try NSWorkspace.shared.unmountAndEjectDevice(at: disk.mount)
                if removeDownload, let download, isDownload(download) {
                    try FileManager.default.trashItem(at: download, resultingItemURL: nil)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't remove the installer"
                alert.informativeText = "\(error.localizedDescription) You can eject the installer in Finder and move the downloaded DMG to Trash later."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    struct Installer: Sendable {
        let mount: URL
        let download: URL?
    }

    nonisolated static func isDownload(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "dmg",
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              url.deletingLastPathComponent().standardizedFileURL == downloads.standardizedFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    nonisolated static func matchingInstallers(build: String, identifier: String) -> [Installer] {
        // hdiutil reports the source file and actual mount point, including
        // quarantine mounts under /private/var and duplicate volume names.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        return images.compactMap { image in
            guard image["writeable"] as? Bool == false,
                  let entities = image["system-entities"] as? [[String: Any]],
                  let path = entities.compactMap({ $0["mount-point"] as? String }).first else { return nil }
            let mount = URL(fileURLWithPath: path, isDirectory: true)
            guard let installerBuild = try? String(contentsOf: mount.appendingPathComponent(".beckon-installer"), encoding: .utf8),
                  let installerNumber = Int(installerBuild), let installedNumber = Int(build),
                  installerNumber <= installedNumber,
                  let infoData = try? Data(contentsOf: mount.appendingPathComponent("Beckon.app/Contents/Info.plist")),
                  let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == identifier,
                  info["CFBundleVersion"] as? String == installerBuild else { return nil }
            let source = (image["image-path"] as? String).map { URL(fileURLWithPath: $0) }
            return Installer(mount: mount, download: source.flatMap { isDownload($0) ? $0 : nil })
        }
    }
}
