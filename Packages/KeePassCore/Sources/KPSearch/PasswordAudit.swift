import Foundation
import KPModel

/// On-device password health check. Nothing leaves the device.
public enum PasswordAudit {
    public enum Issue: Sendable, Equatable, Hashable {
        /// Estimated strength below 50 bits.
        case weak(bits: Int)
        /// The same password is used by other entries.
        case reused(count: Int)
        /// Not changed for more than a year.
        case old(days: Int)
        case expired
    }

    public struct Finding: Sendable, Equatable {
        public let entryID: UUID
        public let title: String
        public let issues: [Issue]
    }

    public static func run(on database: Database, at date: Date = Date()) -> [Finding] {
        let entries = database.activeEntries.filter { !$0.password.isEmpty }
        var usage: [SecretString: Int] = [:]
        for entry in entries {
            usage[entry.password, default: 0] += 1
        }
        return entries.compactMap { entry in
            var issues: [Issue] = []
            let bits = Int(estimatedBits(entry.password.reveal()))
            if bits < 50 {
                issues.append(.weak(bits: bits))
            }
            if let count = usage[entry.password], count > 1 {
                issues.append(.reused(count: count))
            }
            let days = Int(date.timeIntervalSince(entry.times.lastModification) / 86_400)
            if days > 365 {
                issues.append(.old(days: days))
            }
            if entry.times.isExpired(at: date) {
                issues.append(.expired)
            }
            return issues.isEmpty ? nil : Finding(entryID: entry.id, title: entry.title, issues: issues)
        }
    }

    /// A conservative strength estimate: length times log2 of the
    /// character pool, minus penalties for repeats, sequences and very
    /// common passwords. It errs on the low side; it is a nudge, not a
    /// guarantee.
    public static func estimatedBits(_ password: String) -> Double {
        let characters = Array(password)
        guard !characters.isEmpty else { return 0 }
        if commonPasswords.contains(password.lowercased()) { return 0 }

        var pool = 0
        if characters.contains(where: \.isLowercase) { pool += 26 }
        if characters.contains(where: \.isUppercase) { pool += 26 }
        if characters.contains(where: \.isNumber) { pool += 10 }
        if characters.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 33 }
        if characters.contains(where: { !$0.isASCII }) { pool += 100 }

        // Characters that repeat or continue a run (abc, 123, aaa) add
        // little; count them at a quarter.
        var effectiveLength = 1.0
        for index in characters.indices.dropFirst() {
            let previous = characters[index - 1].unicodeScalars.first?.value ?? 0
            let current = characters[index].unicodeScalars.first?.value ?? 0
            let isRun = current == previous || current == previous + 1 || current + 1 == previous
            effectiveLength += isRun ? 0.25 : 1
        }
        return effectiveLength * log2(Double(max(pool, 2)))
    }

    private static let commonPasswords: Set<String> = [
        "123456", "password", "123456789", "12345678", "12345", "qwerty", "abc123", "football", "1234567",
        "monkey", "111111", "letmein", "1234", "1234567890", "dragon", "baseball", "sunshine", "iloveyou",
        "trustno1", "princess", "admin", "welcome", "666666", "passw0rd", "password1", "qwerty123",
        "master", "hello", "freedom", "whatever", "shadow", "superman", "michael", "ninja", "mustang",
    ]
}
