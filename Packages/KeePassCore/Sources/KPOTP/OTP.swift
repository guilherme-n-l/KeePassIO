import Crypto
import Foundation

/// A one-time password generator configuration, as stored in an entry.
///
/// Supports RFC 6238 TOTP (SHA-1, SHA-256, SHA-512, 6–10 digits) and
/// Steam Guard codes, which use TOTP with SHA-1 and a 5-character
/// alphanumeric alphabet.
public struct OTP: Sendable, Equatable {
    public enum Algorithm: String, Sendable, Equatable, CaseIterable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    public enum Kind: Sendable, Equatable {
        case totp(digits: Int)
        case steam
    }

    public var secret: [UInt8]
    public var algorithm: Algorithm
    public var kind: Kind
    /// Time step in seconds.
    public var period: Int
    public var issuer: String?
    public var account: String?

    public init(
        secret: [UInt8],
        algorithm: Algorithm = .sha1,
        kind: Kind = .totp(digits: 6),
        period: Int = 30,
        issuer: String? = nil,
        account: String? = nil
    ) throws(OTPError) {
        guard !secret.isEmpty else { throw .emptySecret }
        guard (1...86_400).contains(period) else { throw .invalidPeriod(period) }
        if case .totp(let digits) = kind, !(6...10).contains(digits) {
            throw .invalidDigits(digits)
        }
        self.secret = secret
        self.algorithm = algorithm
        self.kind = kind
        self.period = period
        self.issuer = issuer
        self.account = account
    }

    /// The code valid at `date`.
    public func code(at date: Date) -> String {
        let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(period)
        let value = truncatedHash(counter: counter)
        switch kind {
        case .totp(let digits):
            var modulus: UInt64 = 1
            for _ in 0..<digits { modulus *= 10 }
            let number = UInt64(value) % modulus
            let text = String(number)
            return String(repeating: "0", count: digits - text.count) + text
        case .steam:
            let alphabet = Array("23456789BCDFGHJKMNPQRTVWXY")
            var remaining = Int(value)
            var code = ""
            for _ in 0..<5 {
                code.append(alphabet[remaining % alphabet.count])
                remaining /= alphabet.count
            }
            return code
        }
    }

    /// Seconds until the code shown at `date` changes.
    public func secondsRemaining(at date: Date) -> Int {
        let elapsed = Int(max(0, date.timeIntervalSince1970)) % period
        return period - elapsed
    }

    /// HMAC of the big-endian counter, dynamically truncated to 31 bits
    /// (RFC 4226 section 5.3).
    private func truncatedHash(counter: UInt64) -> UInt32 {
        let key = SymmetricKey(data: secret)
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let mac: [UInt8] =
            switch algorithm {
            case .sha1: Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
            case .sha256: Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
            case .sha512: Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
            }
        let offset = Int(mac[mac.count - 1] & 0x0f)
        return (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
    }
}

public enum OTPError: Error, Equatable, Sendable {
    case emptySecret
    case invalidSecret
    case invalidPeriod(Int)
    case invalidDigits(Int)
    case unsupportedAlgorithm(String)
    case invalidURI
    case unsupportedType(String)
}
