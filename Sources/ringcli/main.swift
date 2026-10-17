import Foundation
import FindMyRingKit

// Test front end for the shared kit: proves the pure-Swift password-only Find My
// sign-in works against a real account before the GUI is built.
//
//   ringcli list <appleID>
//   ringcli ring <appleID> <device name or id>
//
// Password comes from $RINGCLI_PASSWORD or an interactive (hidden) prompt.

func promptSecret(_ label: String) -> String {
    if let p = ProcessInfo.processInfo.environment["RINGCLI_PASSWORD"], !p.isEmpty { return p }
    guard let c = getpass(label) else { return "" }
    return String(cString: c)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: ringcli list <appleID> | ring <appleID> <device name or id>")
    exit(2)
}
let command = args[1]
let appleID = args[2]
let password = promptSecret("Apple password for \(appleID): ")
guard !password.isEmpty else { print("No password entered."); exit(2) }

let client = FindMyRing(appleID: appleID)

do {
    FileHandle.standardError.write(Data("Signing in...\n".utf8))
    try await client.signIn(password: password)

    switch command {
    case "list":
        let devices = try await client.listDevices()
        print("\(devices.count) devices:")
        for d in devices {
            let flags = [d.isOnline ? "online" : "offline", d.canRing ? "can ring" : "no sound"]
                .joined(separator: ", ")
            print("  \(d.name)  [\(d.model); \(flags)]")
        }
    case "ring":
        guard args.count >= 4 else { print("ring needs a device name or id."); exit(2) }
        let query = args[3].lowercased()
        let devices = try await client.listDevices()
        guard let dev = devices.first(where: {
            $0.id.lowercased() == query || $0.name.lowercased() == query
        }) else {
            print("No device matched \"\(args[3])\". Run `list` to see names."); exit(1)
        }
        try await client.playSound(deviceID: dev.id)
        print(dev.isOnline
            ? "Ringing \(dev.name)."
            : "\(dev.name) looks offline; it will ring when it reconnects.")
    default:
        print("Unknown command \"\(command)\"."); exit(2)
    }
} catch let e as RingError {
    print("Error: \(e.message)")
    exit(1)
} catch {
    print("Error: \(error)")
    exit(1)
}
