import Foundation
import BigInt

/// Client side of Apple's GSA SRP-6a exchange, ported from the `srp` Python
/// package exactly as pyicloud drives it:
///
///   * SHA-256, RFC5054 2048-bit group, generator 2
///   * `rfc5054_enable()`  -> width-pad values to `len(N)` inside `u` and `k`
///   * `no_username_in_x()` -> the username is dropped from `x`, but is still
///     hashed into `M1`
///   * the password fed into SRP is Apple's `s2k`/`s2k_fo` PBKDF2 preprocessing,
///     not the raw password.
///
/// Verified against generated Python `srp` vectors (see FindMyRingKitTests).
struct SRPClient {

    enum PasswordProtocol: String {
        case s2k
        case s2k_fo
    }

    /// RFC5054 2048-bit group modulus.
    static let N = BigUInt(
        "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050" +
        "A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50" +
        "E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B8" +
        "55F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773B" +
        "CA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748" +
        "544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6" +
        "AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6" +
        "94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73",
        radix: 16)!
    static let g = BigUInt(2)
    /// Byte width of N, used for RFC5054 width padding.
    static let width = 256

    /// k = H( PAD(N) | PAD(g) ), computed once.
    static let k: BigUInt = BigUInt(
        Crypto.sha256(
            N.serialize().leftPadded(to: width),
            g.serialize().leftPadded(to: width)
        )
    )

    let username: String
    private let a: BigUInt
    let A: BigUInt

    init(username: String) {
        // get_random_of_length(256): 256 random bytes with the top bit set so
        // the exponent is a full 2048-bit value.
        var aBytes = Crypto.randomBytes(256)
        aBytes[0] |= 0x80
        self.init(username: username, privateEphemeral: aBytes)
    }

    /// Deterministic initializer for cross-checking against known vectors.
    init(username: String, privateEphemeral aBytes: Data) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.a = BigUInt(aBytes)
        self.A = SRPClient.g.power(a, modulus: SRPClient.N)
    }

    /// base64 of long_to_bytes(A), the `a` field of signin/init.
    var publicValueBase64: String { A.serialize().base64EncodedString() }

    struct Proof {
        let m1Base64: String
        let m2Base64: String
    }

    /// Derive the client proof M1 and the expected server proof M2 from the
    /// server's challenge.
    func proof(
        password: String,
        salt: Data,
        serverPublicB: Data,
        protocol proto: PasswordProtocol,
        iterations: Int
    ) -> Proof {
        let N = SRPClient.N
        let g = SRPClient.g
        let k = SRPClient.k
        let width = SRPClient.width
        let B = BigUInt(serverPublicB)

        // u = H( PAD(A) | PAD(B) )
        let u = BigUInt(Crypto.sha256(
            A.serialize().leftPadded(to: width),
            B.serialize().leftPadded(to: width)
        ))

        // x = H( salt | H( ":" | derived ) ), username omitted (no_username_in_x).
        let passwordHash = Crypto.sha256(Data(password.utf8))
        let pbkdfInput: Data = (proto == .s2k_fo)
            ? Data(passwordHash.hexLowercase.utf8)   // s2k_fo: hex string of the hash
            : passwordHash                           // s2k: raw hash bytes
        let derived = Crypto.pbkdf2SHA256(
            password: pbkdfInput, salt: salt, iterations: iterations, keyLength: 32
        )
        let inner = Crypto.sha256(Data([0x3a]) + derived)   // 0x3a == ":"
        let x = BigUInt(Crypto.sha256(salt + inner))

        let v = g.power(x, modulus: N)

        // S = (B - k*v) ^ (a + u*x) mod N, with a non-negative modular base.
        let kv = (k * v) % N
        let base = (B % N + N - kv) % N
        let exponent = a + u * x
        let S = base.power(exponent, modulus: N)

        let K = Crypto.sha256(S.serialize())

        // M1 = H( H(N) XOR H(PAD(g)) | H(I) | salt | A | B | K )
        let hN = Crypto.sha256(N.serialize())
        let hg = Crypto.sha256(g.serialize().leftPadded(to: width))
        var hXor = Data(count: hN.count)
        for i in 0..<hN.count { hXor[i] = hN[i] ^ hg[i] }
        let hI = Crypto.sha256(Data(username.utf8))
        let m1 = Crypto.sha256(hXor + hI + salt + A.serialize() + B.serialize() + K)

        // M2 = H( A | M1 | K )
        let m2 = Crypto.sha256(A.serialize() + m1 + K)

        return Proof(m1Base64: m1.base64EncodedString(), m2Base64: m2.base64EncodedString())
    }
}
