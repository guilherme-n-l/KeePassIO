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
        /// Latin-1 letters and symbols (¡ to ÿ), KeePassXC's "Extended ASCII".
        public static let extendedASCII = CharacterSets(rawValue: 1 << 4)

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
        if set.contains(.extendedASCII) {
            // U+00A1 to U+00FF, without the invisible soft hyphen (U+00AD).
            groups.append((0xA1...0xFF).filter { $0 != 0xAD }.compactMap { UnicodeScalar($0).map(Character.init) })
        }
        if excludingLookalikes {
            groups = groups.map { $0.filter { !lookalikes.contains($0) } }
        }
        return groups.filter { !$0.isEmpty }
    }

    /// Everything that shapes a password, as in KeePassXC's generator.
    public struct Options: Sendable, Equatable {
        public var length: Int
        public var sets: CharacterSets
        public var excludeLookalikes: Bool
        /// At least one character from every chosen set (and from the
        /// "also choose from" characters).
        public var pickFromEveryGroup: Bool
        /// Extra characters to choose from ("Also choose from").
        public var alsoInclude: String
        /// Characters never to use ("Do not include").
        public var exclude: String

        public init(
            length: Int = 20,
            sets: CharacterSets = .all,
            excludeLookalikes: Bool = false,
            pickFromEveryGroup: Bool = true,
            alsoInclude: String = "",
            exclude: String = ""
        ) {
            self.length = length
            self.sets = sets
            self.excludeLookalikes = excludeLookalikes
            self.pickFromEveryGroup = pickFromEveryGroup
            self.alsoInclude = alsoInclude
            self.exclude = exclude
        }

        /// The character groups these options draw from, after removing
        /// look-alikes and excluded characters; duplicates removed.
        public var groups: [[Character]] {
            var groups = PasswordGenerator.characters(in: sets, excludingLookalikes: excludeLookalikes)
            let extra = Array(Set(alsoInclude.filter { !$0.isWhitespace })).sorted()
            if !extra.isEmpty {
                groups.append(extra)
            }
            let excluded = Set(exclude)
            var seen = Set<Character>()
            return groups.map { group in
                group.filter { !excluded.contains($0) && seen.insert($0).inserted }
            }
            .filter { !$0.isEmpty }
        }

        public var entropyBits: Double {
            let poolSize = groups.reduce(0) { $0 + $1.count }
            guard poolSize > 1 else { return 0 }
            return Double(length) * log2(Double(poolSize))
        }
    }

    public init() {}

    public func password(_ options: Options) throws(GeneratorError) -> String {
        var system = SystemRandomNumberGenerator()
        return try password(options, using: &system)
    }

    public func password<Generator: RandomNumberGenerator>(
        _ options: Options,
        using random: inout Generator
    ) throws(GeneratorError) -> String {
        let groups = options.groups
        guard !groups.isEmpty else { throw .noCharacterSets }
        let required = options.pickFromEveryGroup ? groups.count : 1
        guard options.length >= required, options.length <= 1_024 else { throw .invalidLength(options.length) }

        let pool = groups.flatMap(\.self)
        // With "pick from every group", one guaranteed character per group,
        // the rest from the whole pool, then a shuffle so the guaranteed
        // ones aren't at fixed positions.
        var result: [Character] =
            options.pickFromEveryGroup ? groups.map { group in group.randomElement(using: &random) ?? group[0] } : []
        for _ in result.count..<options.length {
            result.append(pool.randomElement(using: &random) ?? pool[0])
        }
        result.shuffle(using: &random)
        return String(result)
    }

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
        try password(Options(length: length, sets: sets, excludeLookalikes: excludingLookalikes), using: &random)
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
