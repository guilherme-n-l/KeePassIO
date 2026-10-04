import Foundation

/// Generates random passwords and passphrases.
///
/// Randomness comes from `SystemRandomNumberGenerator`, which uses the
/// operating system's cryptographically secure source (`arc4random_buf`
/// on Apple platforms, `getrandom` on Linux). Tests can pass a seeded
/// generator instead.
public struct PasswordGenerator: Sendable {
    public struct CharacterSets: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let lowercase = CharacterSets(rawValue: 1 << 0)
        public static let uppercase = CharacterSets(rawValue: 1 << 1)
        public static let digits = CharacterSets(rawValue: 1 << 2)
        public static let symbols = CharacterSets(rawValue: 1 << 3)

        public static let all: CharacterSets = [.lowercase, .uppercase, .digits, .symbols]
    }

    /// Characters that are easy to confuse when read or typed.
    public static let lookalikes: Set<Character> = ["l", "I", "1", "O", "0", "o", "|", "`", "'"]

    public static func characters(in set: CharacterSets, excludingLookalikes: Bool) -> [[Character]] {
        var groups: [[Character]] = []
        if set.contains(.lowercase) { groups.append(Array("abcdefghijklmnopqrstuvwxyz")) }
        if set.contains(.uppercase) { groups.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if set.contains(.digits) { groups.append(Array("0123456789")) }
        if set.contains(.symbols) { groups.append(Array("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")) }
        if excludingLookalikes {
            groups = groups.map { $0.filter { !lookalikes.contains($0) } }
        }
        return groups.filter { !$0.isEmpty }
    }

    public init() {}

    /// A random password of `length` characters drawn from `sets`, with at
    /// least one character from every chosen set.
    public func password(
        length: Int,
        sets: CharacterSets = .all,
        excludingLookalikes: Bool = false
    ) throws(GeneratorError) -> String {
        var system = SystemRandomNumberGenerator()
        return try password(length: length, sets: sets, excludingLookalikes: excludingLookalikes, using: &system)
    }

    public func password<Generator: RandomNumberGenerator>(
        length: Int,
        sets: CharacterSets,
        excludingLookalikes: Bool,
        using random: inout Generator
    ) throws(GeneratorError) -> String {
        let groups = Self.characters(in: sets, excludingLookalikes: excludingLookalikes)
        guard !groups.isEmpty else { throw .noCharacterSets }
        guard length >= groups.count, length <= 1_024 else { throw .invalidLength(length) }

        let pool = groups.flatMap(\.self)
        // One guaranteed character per set, the rest from the whole pool,
        // then a shuffle so the guaranteed ones aren't at fixed positions.
        var result = groups.map { group in group.randomElement(using: &random) ?? group[0] }
        for _ in result.count..<length {
            result.append(pool.randomElement(using: &random) ?? pool[0])
        }
        result.shuffle(using: &random)
        return String(result)
    }

    /// Entropy in bits of a password from this configuration, ignoring the
    /// small reduction from requiring one character per set.
    public static func entropyBits(length: Int, sets: CharacterSets, excludingLookalikes: Bool) -> Double {
        let poolSize = characters(in: sets, excludingLookalikes: excludingLookalikes).reduce(0) { $0 + $1.count }
        guard poolSize > 1 else { return 0 }
        return Double(length) * log2(Double(poolSize))
    }
}

public enum GeneratorError: Error, Equatable, Sendable {
    case noCharacterSets
    case invalidLength(Int)
    case invalidWordCount(Int)
    case wordlistUnavailable
}
