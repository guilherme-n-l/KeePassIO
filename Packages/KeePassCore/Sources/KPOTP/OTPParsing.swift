import Foundation

extension OTP {
    /// Parses an `otpauth://totp/...` URI, the format QR codes and
    /// KeePassXC's `otp` field use. Steam codes are recognized from
    /// `encoder=steam` or an `issuer` of Steam with KeePassXC's
    /// `digits=S` convention.
    public init(uri: String) throws(OTPError) {
        guard let components = URLComponents(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme?.lowercased() == "otpauth"
        else { throw .invalidURI }

        let type = components.host?.lowercased() ?? ""
        guard type == "totp" else { throw .unsupportedType(type) }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value
        }

        guard let secretText = query["secret"], let secret = Base32.decode(secretText), !secret.isEmpty else {
            throw .invalidSecret
        }

        let algorithm: Algorithm
        if let name = query["algorithm"] {
            guard let parsed = Algorithm(rawValue: name.uppercased()) else { throw .unsupportedAlgorithm(name) }
            algorithm = parsed
        } else {
            algorithm = .sha1
        }

        let period = try Self.integer(query["period"], default: 30, error: OTPError.invalidPeriod)

        let kind: Kind
        if query["encoder"]?.lowercased() == "steam" || query["digits"]?.uppercased() == "S" {
            kind = .steam
        } else {
            kind = .totp(digits: try Self.integer(query["digits"], default: 6, error: OTPError.invalidDigits))
        }

        let label = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let labelParts = label.split(separator: ":", maxSplits: 1).map(String.init)
        let account = labelParts.last.flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        let issuer = query["issuer"] ?? (labelParts.count == 2 ? labelParts[0] : nil)

        try self.init(
            secret: secret,
            algorithm: algorithm,
            kind: kind,
            period: period,
            issuer: issuer,
            account: account
        )
    }

    /// Reads the OTP configuration from an entry's custom fields, in either
    /// format KeePass clients use:
    /// - `otp`: an otpauth URI (KeePassXC 2.6 and later, KeePassDX)
    /// - `TOTP Seed` with optional `TOTP Settings` such as `30;6` or `30;S`
    ///   (older KeePassXC and the KeeOtp convention)
    ///
    /// Returns nil when the entry has no OTP fields.
    public init?(fields: [String: String]) throws(OTPError) {
        if let uri = fields["otp"], !uri.isEmpty {
            try self.init(uri: uri)
            return
        }
        guard let seed = fields["TOTP Seed"], !seed.isEmpty else { return nil }
        guard let secret = Base32.decode(seed), !secret.isEmpty else { throw .invalidSecret }

        var period = 30
        var kind = Kind.totp(digits: 6)
        if let settings = fields["TOTP Settings"], !settings.isEmpty {
            let parts = settings.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = parts.first {
                guard let value = Int(first) else { throw .invalidPeriod(0) }
                period = value
            }
            if parts.count > 1 {
                if parts[1].uppercased() == "S" {
                    kind = .steam
                } else {
                    guard let digits = Int(parts[1]) else { throw .invalidDigits(0) }
                    kind = .totp(digits: digits)
                }
            }
        }
        try self.init(secret: secret, kind: kind, period: period)
    }

    /// A configuration from a secret typed in by hand: base32, as sites
    /// show it, ignoring spaces, dashes and case.
    public init(
        base32Secret: String,
        algorithm: Algorithm = .sha1,
        kind: Kind = .totp(digits: 6),
        period: Int = 30,
        issuer: String? = nil,
        account: String? = nil
    ) throws(OTPError) {
        let cleaned = base32Secret.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard let secret = Base32.decode(cleaned), !secret.isEmpty else { throw .invalidSecret }
        try self.init(
            secret: secret,
            algorithm: algorithm,
            kind: kind,
            period: period,
            issuer: issuer,
            account: account
        )
    }

    /// The otpauth URI for this configuration, as written to the `otp`
    /// field and shown as a QR code.
    public var uri: String {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        let label = [issuer, account].compactMap { $0 }.joined(separator: ":")
        components.path = "/" + label
        var items = [
            URLQueryItem(name: "secret", value: Base32.encode(secret)),
            URLQueryItem(name: "period", value: String(period)),
            URLQueryItem(name: "algorithm", value: algorithm.rawValue),
        ]
        switch kind {
        case .totp(let digits):
            items.append(URLQueryItem(name: "digits", value: String(digits)))
        case .steam:
            items.append(URLQueryItem(name: "encoder", value: "steam"))
        }
        if let issuer {
            items.append(URLQueryItem(name: "issuer", value: issuer))
        }
        components.queryItems = items
        return components.string ?? ""
    }

    private static func integer(
        _ text: String?,
        default defaultValue: Int,
        error: (Int) -> OTPError
    ) throws(OTPError) -> Int {
        guard let text else { return defaultValue }
        guard let value = Int(text) else { throw error(0) }
        return value
    }
}
