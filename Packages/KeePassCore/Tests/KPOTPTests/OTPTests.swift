import Foundation
import Testing

@testable import KPOTP

struct OTPTests {
    struct RFCVector: Sendable {
        let time: TimeInterval
        let sha1: String
        let sha256: String
        let sha512: String
    }

    // RFC 6238 appendix B: 8-digit codes for each algorithm.
    static let rfcVectors = [
        RFCVector(time: 59, sha1: "94287082", sha256: "46119246", sha512: "90693936"),
        RFCVector(time: 1_111_111_109, sha1: "07081804", sha256: "68084774", sha512: "25091201"),
        RFCVector(time: 1_111_111_111, sha1: "14050471", sha256: "67062674", sha512: "99943326"),
        RFCVector(time: 1_234_567_890, sha1: "89005924", sha256: "91819424", sha512: "93441116"),
        RFCVector(time: 2_000_000_000, sha1: "69279037", sha256: "90698825", sha512: "38618901"),
        RFCVector(time: 20_000_000_000, sha1: "65353130", sha256: "77737706", sha512: "47863826"),
    ]

    @Test(arguments: rfcVectors)
    func rfc6238Vectors(vector: RFCVector) throws {
        let date = Date(timeIntervalSince1970: vector.time)
        let sha1 = try OTP(secret: Array("12345678901234567890".utf8), algorithm: .sha1, kind: .totp(digits: 8))
        let sha256 = try OTP(
            secret: Array("12345678901234567890123456789012".utf8),
            algorithm: .sha256,
            kind: .totp(digits: 8)
        )
        let sha512 = try OTP(
            secret: Array("1234567890123456789012345678901234567890123456789012345678901234".utf8),
            algorithm: .sha512,
            kind: .totp(digits: 8)
        )
        #expect(sha1.code(at: date) == vector.sha1)
        #expect(sha256.code(at: date) == vector.sha256)
        #expect(sha512.code(at: date) == vector.sha512)
    }

    // Expected values computed independently with Python's hmac module.
    @Test(arguments: [
        (TimeInterval(0), "VH8YJ", "282760"),
        (1_700_000_000, "2KM2P", "324550"),
        (1_234_567_890, "K8G5W", "742275"),
    ])
    func steamAndSixDigitCodes(time: TimeInterval, steam: String, sixDigits: String) throws {
        let secret = try #require(Base32.decode("JBSWY3DPEHPK3PXP"))
        let date = Date(timeIntervalSince1970: time)
        #expect(try OTP(secret: secret, kind: .steam).code(at: date) == steam)
        #expect(try OTP(secret: secret).code(at: date) == sixDigits)
    }

    @Test func secondsRemaining() throws {
        let otp = try OTP(secret: [1, 2, 3])
        #expect(otp.secondsRemaining(at: Date(timeIntervalSince1970: 60)) == 30)
        #expect(otp.secondsRemaining(at: Date(timeIntervalSince1970: 89)) == 1)
    }

    @Test func rejectsInvalidConfigurations() {
        #expect(throws: OTPError.emptySecret) { try OTP(secret: []) }
        #expect(throws: OTPError.invalidDigits(5)) { try OTP(secret: [1], kind: .totp(digits: 5)) }
        #expect(throws: OTPError.invalidPeriod(0)) { try OTP(secret: [1], period: 0) }
    }
}

struct OTPParsingTests {
    @Test func parsesFullURI() throws {
        let uri =
            "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP"
            + "&issuer=Example&algorithm=SHA256&digits=8&period=60"
        let otp = try OTP(uri: uri)
        #expect(otp.issuer == "Example")
        #expect(otp.account == "alice@example.com")
        #expect(otp.algorithm == .sha256)
        #expect(otp.kind == .totp(digits: 8))
        #expect(otp.period == 60)
        #expect(otp.secret == Base32.decode("JBSWY3DPEHPK3PXP"))
    }

    @Test func appliesDefaults() throws {
        let otp = try OTP(uri: "otpauth://totp/alice?secret=jbswy3dpehpk3pxp")
        #expect(otp.algorithm == .sha1)
        #expect(otp.kind == .totp(digits: 6))
        #expect(otp.period == 30)
        #expect(otp.issuer == nil)
        #expect(otp.account == "alice")
    }

    @Test(arguments: [
        "otpauth://totp/Steam:bob?secret=JBSWY3DPEHPK3PXP&encoder=steam",
        "otpauth://totp/Steam:bob?secret=JBSWY3DPEHPK3PXP&digits=S",
    ])
    func recognizesSteam(uri: String) throws {
        #expect(try OTP(uri: uri).kind == .steam)
    }

    @Test func rejectsBadURIs() {
        #expect(throws: OTPError.invalidURI) { try OTP(uri: "https://example.com") }
        #expect(throws: OTPError.unsupportedType("hotp")) { try OTP(uri: "otpauth://hotp/a?secret=AA") }
        #expect(throws: OTPError.invalidSecret) { try OTP(uri: "otpauth://totp/a?secret=!!!") }
        #expect(throws: OTPError.unsupportedAlgorithm("MD5")) {
            try OTP(uri: "otpauth://totp/a?secret=JBSWY3DP&algorithm=MD5")
        }
    }

    @Test func uriRoundTrips() throws {
        let original = try OTP(
            secret: Array("secret-bytes".utf8),
            algorithm: .sha512,
            kind: .totp(digits: 7),
            period: 45,
            issuer: "Example",
            account: "alice"
        )
        #expect(try OTP(uri: original.uri) == original)

        let steam = try OTP(secret: [9, 8, 7], kind: .steam, issuer: "Steam", account: "bob")
        #expect(try OTP(uri: steam.uri) == steam)
    }

    @Test func readsKeePassXCFields() throws {
        let fromURI = try OTP(fields: ["otp": "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP"])
        #expect(fromURI?.kind == .totp(digits: 6))

        let legacy = try OTP(fields: ["TOTP Seed": "JBSWY3DPEHPK3PXP", "TOTP Settings": "60;8"])
        #expect(legacy?.period == 60)
        #expect(legacy?.kind == .totp(digits: 8))

        let legacySteam = try OTP(fields: ["TOTP Seed": "JBSWY3DPEHPK3PXP", "TOTP Settings": "30;S"])
        #expect(legacySteam?.kind == .steam)

        #expect(try OTP(fields: ["UserName": "alice"]) == nil)
    }
}

struct Base32Tests {
    // RFC 4648 section 10.
    @Test(arguments: [
        ("", ""),
        ("f", "MY"),
        ("fo", "MZXQ"),
        ("foo", "MZXW6"),
        ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"),
        ("foobar", "MZXW6YTBOI"),
    ])
    func rfc4648Vectors(plain: String, encoded: String) {
        #expect(Base32.encode(Array(plain.utf8)) == encoded)
        #expect(Base32.decode(encoded) == Array(plain.utf8))
    }

    @Test func toleratesFormatting() {
        #expect(Base32.decode("mzxw 6ytb-oi======") == Array("foobar".utf8))
        #expect(Base32.decode("MZXW1") == nil)
    }
}
