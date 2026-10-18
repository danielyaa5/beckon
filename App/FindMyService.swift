import Foundation
import FindMyRingKit

/// The app's one door to iCloud. Keeps a signed-in client in memory for a few
/// minutes, so a refresh followed by a ring (or a burst of rings) signs in
/// once; nothing is written to disk. A stale or rejected session gets one
/// fresh sign-in and a retry.
actor FindMyService {
    /// How long a signed-in client is reused. Apple's web session lasts longer;
    /// this only bounds how stale a reused one can be.
    private static let reuseFor: TimeInterval = 10 * 60

    private var client: FindMyRing?
    private var clientAppleID = ""
    private var signedInAt = Date.distantPast
    private var signingIn: Task<FindMyRing, Error>?

    func devices(appleID: String, password: String) async throws -> [FoundDevice] {
        let usedCachedSession = client != nil && clientAppleID == appleID
            && Date().timeIntervalSince(signedInAt) < Self.reuseFor
        let reused = try await signedIn(appleID: appleID, password: password, fresh: false)
        do {
            let list = try await reused.listDevices()
            // A dead session can come back as an empty list rather than an error.
            if !list.isEmpty || !usedCachedSession { return list }
        } catch let error as RingError where error.kind == .server {}
        let fresh = try await signedIn(appleID: appleID, password: password, fresh: true)
        return try await fresh.listDevices()
    }

    func ring(deviceID: String, appleID: String, password: String) async throws {
        let reused = try await signedIn(appleID: appleID, password: password, fresh: false)
        do {
            try await reused.playSound(deviceID: deviceID)
            return
        } catch let error as RingError where error.kind == .server {}
        let fresh = try await signedIn(appleID: appleID, password: password, fresh: true)
        try await fresh.playSound(deviceID: deviceID)
    }

    func forget() {
        client = nil
        signedInAt = .distantPast
    }

    private func signedIn(appleID: String, password: String, fresh: Bool) async throws -> FindMyRing {
        if !fresh, let client, clientAppleID == appleID,
           Date().timeIntervalSince(signedInAt) < Self.reuseFor {
            return client
        }
        if let signingIn { return try await signingIn.value }
        let task = Task { () throws -> FindMyRing in
            let c = FindMyRing(appleID: appleID)
            try await c.signIn(password: password)
            return c
        }
        signingIn = task
        defer { signingIn = nil }
        let c = try await task.value
        client = c
        clientAppleID = appleID
        signedInAt = Date()
        return c
    }
}
