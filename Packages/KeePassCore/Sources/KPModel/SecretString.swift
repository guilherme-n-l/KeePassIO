import Foundation

/// A protected field value (passwords, OTP secrets, protected custom
/// fields).
///
/// The bytes live in a private buffer that is zeroed when the last copy
/// is released, and they never appear in `description`, `debugDescription`
/// or mirrors, so a stray `print` or log statement can't leak them. Call
/// `reveal()` only at the point of use (showing, copying, filling).
public struct SecretString: Sendable, Equatable, Hashable, ExpressibleByStringLiteral,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    private final class Storage: @unchecked Sendable {
        // Written only in init and deinit, so sharing it between threads is
        // safe without a lock.
        var bytes: [UInt8]

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        deinit {
            bytes.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                // memset_s and explicit_bzero are guaranteed not to be
                // removed as dead stores, unlike a plain memset before free.
                #if canImport(Darwin)
                    _ = memset_s(base, buffer.count, 0, buffer.count)
                #else
                    explicit_bzero(base, buffer.count)
                #endif
            }
        }
    }

    private let storage: Storage

    public init(_ value: String) {
        storage = Storage(Array(value.utf8))
    }

    public init(bytes: [UInt8]) {
        storage = Storage(bytes)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public static let empty = SecretString("")

    public var isEmpty: Bool { storage.bytes.isEmpty }
    /// Length in UTF-8 bytes; safe to log.
    public var byteCount: Int { storage.bytes.count }

    /// The value as text. Bytes that aren't valid UTF-8 (possible only via
    /// `init(bytes:)`) become U+FFFD rather than failing, so a damaged
    /// field still shows something.
    public func reveal() -> String {
        String(decoding: storage.bytes, as: UTF8.self)  // swiftlint:disable:this optional_data_string_conversion
    }

    public func withBytes<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        try storage.bytes.withUnsafeBufferPointer(body)
    }

    public static func == (lhs: SecretString, rhs: SecretString) -> Bool {
        lhs.storage === rhs.storage || lhs.storage.bytes == rhs.storage.bytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storage.bytes)
    }

    public var description: String { "<secret>" }
    public var debugDescription: String { "<secret: \(byteCount) bytes>" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
