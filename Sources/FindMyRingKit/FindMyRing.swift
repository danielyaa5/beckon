import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A standalone, pure-Swift port of the password-only ("pause 2FA") Find My
/// sign-in that pyicloud performs, plus the two Find My calls this app needs:
/// list devices and play a sound.
///
/// The whole thing lives inside one `URLSession` with an **ephemeral** (memory
/// only) cookie store, so no session or cookie ever touches disk. A signed-in
/// client lasts only as long as the object; nothing is persisted but the
/// password (which the app keeps in the Keychain, not here).
///
/// An actor, so one signed-in client can be shared by several tasks: its
/// session state only changes on the actor.
public actor FindMyRing {

    // MARK: Constants (match pyicloud exactly)

    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3.1 Safari/605.1.15"
    static let oauthKey = "d39ba9916b7251055b22c7f910e2ea796ee65e98b2ddecea8f5dde8d9d1a815d"
    static let idmsa = "https://idmsa.apple.com"
    static let authEndpoint = idmsa + "/appleauth/auth"
    static let home = "https://www.icloud.com"
    static let setupEndpoint = "https://setup.icloud.com/setup/ws/1"
    static let clientBuildNumber = "2534Project66"
    static let clientMasteringNumber = "2534B22"

    static let fdClientInfo: String = {
        let dict: [String: String] = [
            "U": userAgent, "L": "en-US", "Z": "GMT+00:00", "V": "1.1", "F": "",
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }()

    /// Response headers pyicloud copies into its session state.
    static let headerMap: [String: String] = [
        "X-Apple-ID-Account-Country": "account_country",
        "X-Apple-ID-Session-Id": "session_id",
        "X-Apple-Auth-Attributes": "auth_attributes",
        "X-Apple-Session-Token": "session_token",
        "X-Apple-TwoSV-Trust-Token": "trust_token",
        "X-Apple-TwoSV-Trust-Eligible": "trust_eligible",
        "X-Apple-OAuth-Grant-Code": "grant_code",
        "scnt": "scnt",
    ]

    // MARK: State

    private let appleID: String
    private let session: URLSession
    private let clientID = UUID().uuidString.lowercased()
    private var state: [String: String] = [:]

    private var findmeBase: String?
    private var queryParams: [URLQueryItem] = []

    public init(appleID: String) {
        self.appleID = appleID
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Public API

    /// Sign in with the password alone. Throws RingError on failure.
    public func signIn(password: String) async throws {
        try await authorizeSignin()
        let srp = SRPClient(username: appleID)
        let challenge = try await signinInit(srp: srp)
        try await signinComplete(srp: srp, password: password, challenge: challenge)
        try await accountLogin()
    }

    /// List the account's devices (initClient).
    public func listDevices() async throws -> [FoundDevice] {
        let json = try await fmipPOST("initClient", body: [
            "clientContext": [
                "appName": "iCloud Find (Web)",
                "appVersion": "2.0",
                "apiVersion": "3.0",
                "deviceListVersion": 1,
                "fmly": false,
                "timezone": "US/Pacific",
                "inactiveTime": 0,
            ],
        ])
        // A reply without a device list is an error, not "no devices":
        // treating it as empty would wipe the app's saved list.
        guard let content = json["content"] as? [[String: Any]] else {
            throw RingError(.server, "Apple's device list couldn't be read. Try again later.")
        }
        return content.map { d in
            let features = d["features"] as? [String: Any] ?? [:]
            let status = d["batteryStatus"] as? String
            let level = (d["batteryLevel"] as? NSNumber)?.doubleValue
            return FoundDevice(
                id: (d["id"] as? String) ?? "",
                name: (d["name"] as? String) ?? "",
                model: (d["deviceDisplayName"] as? String) ?? "",
                deviceClass: (d["deviceClass"] as? String) ?? "",
                isOnline: (d["deviceStatus"] as? String) == "200",
                canRing: (features["SND"] as? Bool) ?? false,
                // Apple sends 0 with "Unknown" when it has no reading.
                batteryLevel: level.flatMap { $0 > 0 || (status != nil && status != "Unknown") ? min($0, 1) : nil },
                batteryStatus: status,
                location: Self.location(d["location"] as? [String: Any])
            )
        }
    }

    static func location(_ l: [String: Any]?) -> FoundDevice.Location? {
        guard let l,
              let lat = (l["latitude"] as? NSNumber)?.doubleValue,
              let lon = (l["longitude"] as? NSNumber)?.doubleValue,
              lat != 0 || lon != 0
        else { return nil }
        let ms = (l["timeStamp"] as? NSNumber)?.doubleValue ?? 0
        return FoundDevice.Location(
            latitude: lat,
            longitude: lon,
            accuracy: (l["horizontalAccuracy"] as? NSNumber)?.doubleValue ?? 0,
            timestamp: ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : Date()
        )
    }

    /// Play a sound on one device id.
    public func playSound(deviceID: String, subject: String = "Beckon") async throws {
        _ = try await fmipPOST("playSound", body: [
            "device": deviceID,
            "subject": subject,
            "clientContext": ["fmly": true],
        ])
    }

    // MARK: Sign-in steps

    private func authorizeSignin() async throws {
        var comps = URLComponents(string: Self.authEndpoint + "/authorize/signin")!
        comps.queryItems = [
            .init(name: "frame_id", value: clientID),
            .init(name: "skVersion", value: "7"),
            .init(name: "iframeid", value: clientID),
            .init(name: "client_id", value: Self.oauthKey),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.home),
            .init(name: "response_mode", value: "web_message"),
            .init(name: "state", value: clientID),
            .init(name: "authVersion", value: "latest"),
        ]
        _ = try await send(method: "GET", url: comps.url!, headers: authHeaders(), body: nil)
    }

    private struct Challenge {
        let salt: Data
        let b: Data
        let c: String
        let iterations: Int
        let proto: SRPClient.PasswordProtocol
    }

    private func signinInit(srp: SRPClient) async throws -> Challenge {
        let (data, _) = try await send(
            method: "POST",
            url: URL(string: Self.authEndpoint + "/signin/init")!,
            headers: authHeaders(),
            body: json([
                "a": srp.publicValueBase64,
                "accountName": appleID,
                "protocols": ["s2k", "s2k_fo"],
            ])
        )
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let saltB64 = obj["salt"] as? String, let salt = Data(base64Encoded: saltB64),
              let bB64 = obj["b"] as? String, let b = Data(base64Encoded: bB64),
              let c = obj["c"] as? String
        else { throw RingError(.server, "Apple's sign-in response was not in the expected form.") }
        let iterations = (obj["iteration"] as? Int) ?? (obj["iteration"] as? NSNumber)?.intValue ?? 0
        // PBKDF2 traps on 0 rounds (and UInt32 on a negative count), which
        // would crash the app or the widget on a malformed answer.
        guard (1...10_000_000).contains(iterations) else {
            throw RingError(.server, "Apple's sign-in response was not in the expected form.")
        }
        let proto = SRPClient.PasswordProtocol(rawValue: (obj["protocol"] as? String) ?? "s2k") ?? .s2k
        return Challenge(salt: salt, b: b, c: c, iterations: iterations, proto: proto)
    }

    private func signinComplete(srp: SRPClient, password: String, challenge: Challenge) async throws {
        let proof = srp.proof(
            password: password,
            salt: challenge.salt,
            serverPublicB: challenge.b,
            protocol: challenge.proto,
            iterations: challenge.iterations
        )
        var comps = URLComponents(string: Self.authEndpoint + "/signin/complete")!
        comps.queryItems = [.init(name: "isRememberMeEnabled", value: "true")]
        // Apple answers this with 409 (2FA wanted) but still mints the session
        // token in a header when pause2FA is set, so don't treat non-2xx as
        // fatal here — check for the token afterwards.
        let (data, http) = try await send(
            method: "POST", url: comps.url!, headers: authHeaders(),
            body: json([
                "accountName": appleID,
                "c": challenge.c,
                "m1": proof.m1Base64,
                "m2": proof.m2Base64,
                "rememberMe": true,
                "trustTokens": [],
                "pause2FA": true,
            ]),
            allowErrorStatus: true
        )
        guard state["session_token"] == nil else { return }
        // Only a real rejection may count as a wrong password: the app forgets
        // a password Apple rejects, so an outage or rate limit mustn't look
        // like one.
        let code = http.statusCode
        if isAccountLocked(data) {
            throw RingError(.accountLocked, "Apple says this account is locked. Unlock it, then try again.")
        }
        if code == 401 || serviceErrorCodes(data).contains("-20101") {
            throw RingError(.badCredentials, "Apple did not accept that Apple Account and password.")
        }
        switch code {
        case 409:
            throw RingError(.twoFactorWanted, "Apple wants a verification code for this account, so password-only sign-in isn't available.")
        case 412:
            throw RingError(.server, "Apple wants you to review your Apple Account first. Sign in at account.apple.com, then try again.")
        case 429:
            throw RingError(.server, "Apple is limiting sign-ins right now. Try again in a few minutes.")
        case 500...599:
            throw RingError(.server, "Apple's sign-in service had a problem (HTTP \(code)). Try again later.")
        default:
            throw RingError(.server, "Apple's sign-in answered HTTP \(code) without signing in.")
        }
    }

    private func accountLogin() async throws {
        let (data, _) = try await send(
            method: "POST",
            url: URL(string: Self.setupEndpoint + "/accountLogin")!,
            headers: setupHeaders(),
            body: json([
                "dsWebAuthToken": state["session_token"] ?? "",
                "accountCountryCode": state["account_country"] ?? "",
                "extended_login": true,
                "trustToken": state["trust_token"] ?? "",
            ])
        )
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw RingError(.server, "Apple's account-login response could not be read.") }

        let webservices = obj["webservices"] as? [String: Any]
        let findme = webservices?["findme"] as? [String: Any]
        guard var base = findme?["url"] as? String else {
            throw RingError(.twoFactorWanted,
                "Apple did not grant password-only Find My for this account.")
        }
        if base.hasSuffix("/") { base.removeLast() }
        findmeBase = base

        let dsid = ((obj["dsInfo"] as? [String: Any])?["dsid"] as? String)
            ?? ((obj["dsInfo"] as? [String: Any])?["dsid"] as? NSNumber)?.stringValue
        queryParams = [
            .init(name: "clientBuildNumber", value: Self.clientBuildNumber),
            .init(name: "clientMasteringNumber", value: Self.clientMasteringNumber),
            .init(name: "clientId", value: clientID),
        ]
        if let dsid { queryParams.append(.init(name: "dsid", value: dsid)) }
    }

    // MARK: Find My POST

    private func fmipPOST(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard let base = findmeBase else { throw RingError(.server, "Not signed in.") }
        var comps = URLComponents(string: base + "/fmipservice/client/web/" + endpoint)!
        comps.queryItems = queryParams
        let (data, _) = try await send(method: "POST", url: comps.url!, headers: setupHeaders(), body: json(body))
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: HTTP

    private func authHeaders() -> [String: String] {
        var h: [String: String] = [
            "Accept": "application/json, text/javascript",
            "Content-Type": "application/json",
            "User-Agent": Self.userAgent,
            "Origin": Self.home,
            "Referer": Self.idmsa,
            "X-Apple-OAuth-Client-Id": Self.oauthKey,
            "X-Apple-OAuth-Client-Type": "firstPartyAuth",
            "X-Apple-OAuth-Redirect-URI": Self.home,
            "X-Apple-OAuth-Require-Grant-Code": "true",
            "X-Apple-OAuth-Response-Mode": "web_message",
            "X-Apple-OAuth-Response-Type": "code",
            "X-Apple-OAuth-State": clientID,
            "X-Apple-Widget-Key": Self.oauthKey,
            "X-Apple-Frame-Id": clientID,
            "X-Apple-FD-Client-Info": Self.fdClientInfo,
        ]
        if let v = state["scnt"] { h["scnt"] = v }
        if let v = state["session_id"] { h["X-Apple-ID-Session-Id"] = v }
        if let v = state["auth_attributes"] { h["X-Apple-Auth-Attributes"] = v }
        return h
    }

    private func setupHeaders() -> [String: String] {
        [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": Self.userAgent,
            "Origin": Self.home,
            "Referer": Self.home + "/",
        ]
    }

    private func json(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func isAccountLocked(_ data: Data) -> Bool {
        serviceErrorCodes(data).contains("-20209")
    }

    /// The codes in Apple's `serviceErrors` list ("-20101" wrong password,
    /// "-20209" locked).
    private func serviceErrorCodes(_ data: Data) -> [String] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let errors = obj["serviceErrors"] as? [[String: Any]] else { return [] }
        return errors.map { "\($0["code"] ?? "")" }
    }

    @discardableResult
    private func send(
        method: String, url: URL, headers: [String: String], body: Data?,
        allowErrorStatus: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw RingError(.network, "Could not reach Apple: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw RingError(.server, "Apple returned a response that could not be read.")
        }
        for (header, key) in Self.headerMap {
            if let v = http.value(forHTTPHeaderField: header) { state[key] = v }
        }
        if !allowErrorStatus && !(200...299).contains(http.statusCode) {
            if isAccountLocked(data) {
                throw RingError(.accountLocked, "Apple says this account is locked.")
            }
            throw RingError(.server, "Apple returned HTTP \(http.statusCode).")
        }
        return (data, http)
    }
}
