import Foundation

/// Generates diceware-style passphrases from a wordlist.
///
/// The bundled English list is the EFF large wordlist (7,776 words, so
/// each word adds about 12.9 bits of entropy). Lists for other languages
/// can be added as `<language>_wordlist.txt` resources in the same
/// `dice-roll<TAB>word` format.
public struct PassphraseGenerator: Sendable {
    public let words: [String]

    public init(words: [String]) throws(GeneratorError) {
        guard words.count >= 2 else { throw .wordlistUnavailable }
        self.words = words
    }

    /// The bundled EFF large wordlist.
    public static func english() throws(GeneratorError) -> PassphraseGenerator {
        guard let url = Bundle.module.url(forResource: "eff_large_wordlist", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw .wordlistUnavailable }
        let words = text.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        }
        return try PassphraseGenerator(words: words)
    }

    /// How each word is written, as in KeePassXC.
    public enum WordCase: String, Codable, Sendable, CaseIterable {
        case lower
        case upper
        case title

        func apply(to word: String) -> String {
            switch self {
            case .lower: word.lowercased()
            case .upper: word.uppercased()
            case .title: word.prefix(1).uppercased() + word.dropFirst()
            }
        }
    }

    public func passphrase(wordCount: Int, separator: String, wordCase: WordCase) throws(GeneratorError) -> String {
        var system = SystemRandomNumberGenerator()
        return try passphrase(wordCount: wordCount, separator: separator, wordCase: wordCase, using: &system)
    }

    public func passphrase<Generator: RandomNumberGenerator>(
        wordCount: Int,
        separator: String,
        wordCase: WordCase,
        using random: inout Generator
    ) throws(GeneratorError) -> String {
        guard (1...64).contains(wordCount) else { throw .invalidWordCount(wordCount) }
        return (0..<wordCount).map { _ in
            wordCase.apply(to: words.randomElement(using: &random) ?? words[0])
        }
        .joined(separator: separator)
    }

    public func passphrase(
        wordCount: Int,
        separator: String = "-",
        capitalize: Bool = false
    ) throws(GeneratorError) -> String {
        var system = SystemRandomNumberGenerator()
        return try passphrase(wordCount: wordCount, separator: separator, capitalize: capitalize, using: &system)
    }

    public func passphrase<Generator: RandomNumberGenerator>(
        wordCount: Int,
        separator: String,
        capitalize: Bool,
        using random: inout Generator
    ) throws(GeneratorError) -> String {
        guard (1...64).contains(wordCount) else { throw .invalidWordCount(wordCount) }
        return (0..<wordCount).map { _ in
            let word = words.randomElement(using: &random) ?? words[0]
            return capitalize ? word.prefix(1).uppercased() + word.dropFirst() : word
        }
        .joined(separator: separator)
    }

    public func entropyBits(wordCount: Int) -> Double {
        Double(wordCount) * log2(Double(words.count))
    }
}
