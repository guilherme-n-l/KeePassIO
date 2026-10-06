/// RFC 4648 Base32 decoding, as used for OTP secrets.
///
/// Accepts lowercase letters, spaces, hyphens and missing padding, since
/// secrets are often typed or copied with those.
enum Base32 {
    static func decode(_ text: String) -> [UInt8]? {
        var buffer: UInt32 = 0
        var bitCount = 0
        var output: [UInt8] = []
        output.reserveCapacity(text.utf8.count * 5 / 8)

        for byte in text.utf8 {
            let value: UInt32
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): value = UInt32(byte - UInt8(ascii: "A"))
            case UInt8(ascii: "a")...UInt8(ascii: "z"): value = UInt32(byte - UInt8(ascii: "a"))
            case UInt8(ascii: "2")...UInt8(ascii: "7"): value = UInt32(byte - UInt8(ascii: "2")) + 26
            case UInt8(ascii: "="), UInt8(ascii: " "), UInt8(ascii: "-"): continue
            default: return nil
            }
            buffer = (buffer << 5) | value
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((buffer >> UInt32(bitCount)) & 0xff))
            }
        }
        return output
    }

    static func encode(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var output = ""
        var buffer: UInt32 = 0
        var bitCount = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[Int((buffer >> UInt32(bitCount)) & 0x1f)])
            }
        }
        if bitCount > 0 {
            output.append(alphabet[Int((buffer << UInt32(5 - bitCount)) & 0x1f)])
        }
        return output
    }
}
