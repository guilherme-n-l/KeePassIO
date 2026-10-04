import Testing

@testable import KPGenerator

/// Deterministic generator for reproducible tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct PasswordGeneratorTests {
    let generator = PasswordGenerator()

    @Test(arguments: [4, 16, 64, 1_024])
    func containsEveryChosenSet(length: Int) throws {
        var random = SeededGenerator(state: UInt64(length))
        for _ in 0..<50 {
            let password = try generator.password(
                length: length,
                sets: .all,
                excludingLookalikes: false,
                using: &random
            )
            #expect(password.count == length)
            #expect(password.contains { $0.isLowercase })
            #expect(password.contains { $0.isUppercase })
            #expect(password.contains { $0.isNumber })
            #expect(password.contains { !$0.isLetter && !$0.isNumber })
        }
    }

    @Test func respectsSetsAndLookalikes() throws {
        var random = SeededGenerator(state: 7)
        let password = try generator.password(
            length: 500,
            sets: [.lowercase, .digits],
            excludingLookalikes: true,
            using: &random
        )
        #expect(password.allSatisfy { $0.isLowercase || $0.isNumber })
        #expect(!password.contains { PasswordGenerator.lookalikes.contains($0) })
    }

    @Test func rejectsImpossibleRequests() {
        #expect(throws: GeneratorError.noCharacterSets) { try generator.password(length: 10, sets: []) }
        #expect(throws: GeneratorError.invalidLength(3)) { try generator.password(length: 3, sets: .all) }
        #expect(throws: GeneratorError.invalidLength(2_000)) { try generator.password(length: 2_000) }
    }

    @Test func systemRandomPasswordsDiffer() throws {
        let passwords = try (0..<20).map { _ in try generator.password(length: 20) }
        #expect(Set(passwords).count == 20)
    }

    @Test func entropy() {
        let bits = PasswordGenerator.entropyBits(length: 20, sets: .all, excludingLookalikes: false)
        // 94 printable ASCII characters: log2(94) ≈ 6.555 bits each.
        #expect(abs(bits - 131.1) < 0.1)
    }
}

struct PassphraseGeneratorTests {
    @Test func bundledWordlistIsTheEFFLargeList() throws {
        let generator = try PassphraseGenerator.english()
        #expect(generator.words.count == 7_776)
        #expect(Set(generator.words).count == 7_776)
        #expect(generator.words.first == "abacus")
        #expect(generator.words.last == "zoom")
        #expect(abs(generator.entropyBits(wordCount: 6) - 77.5) < 0.1)
    }

    @Test func buildsPassphrases() throws {
        let generator = try PassphraseGenerator.english()
        var random = SeededGenerator(state: 42)
        let passphrase = try generator.passphrase(wordCount: 5, separator: " ", capitalize: true, using: &random)
        let words = passphrase.split(separator: " ")
        #expect(words.count == 5)
        for word in words {
            #expect(word.first?.isUppercase == true)
            #expect(generator.words.contains(word.lowercased()))
        }
    }

    @Test func rejectsBadInput() throws {
        #expect(throws: GeneratorError.wordlistUnavailable) { try PassphraseGenerator(words: ["one"]) }
        let generator = try PassphraseGenerator.english()
        #expect(throws: GeneratorError.invalidWordCount(0)) { try generator.passphrase(wordCount: 0) }
    }
}
