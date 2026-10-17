import Foundation
import CommonCrypto
import CryptoKit

/// Small crypto helpers used by the SRP client. Kept deliberately thin and
/// dependency-free (CryptoKit + CommonCrypto, both in the OS) so the only
/// third-party dependency in the whole kit is the big-integer library.
enum Crypto {

    /// SHA-256 digest of `data` as 32 raw bytes.
    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Concatenate, then SHA-256. Matches pyicloud's `H(hash, *args)` with no
    /// width padding: the arguments are joined and hashed as-is.
    static func sha256(_ parts: Data...) -> Data {
        var acc = Data()
        for p in parts { acc.append(p) }
        return sha256(acc)
    }

    /// PBKDF2-HMAC-SHA256. Mirrors Python's
    /// `hashlib.pbkdf2_hmac("sha256", password, salt, iterations, keyLength)`.
    static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var out = Data(count: keyLength)
        let status = out.withUnsafeMutableBytes { outPtr -> Int32 in
            salt.withUnsafeBytes { saltPtr -> Int32 in
                password.withUnsafeBytes { pwPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed with status \(status)")
        return out
    }

    /// Cryptographically secure random bytes.
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return data
    }
}

extension Data {
    /// Lowercase hex, matching Python `bytes.hex()`.
    var hexLowercase: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Left-pad with zero bytes to `width`. Mirrors pyicloud's RFC5054 width
    /// padding in `H(..., width=len(N))`. A value already `>= width` bytes is
    /// returned unchanged.
    func leftPadded(to width: Int) -> Data {
        guard count < width else { return self }
        return Data(repeating: 0, count: width - count) + self
    }
}
