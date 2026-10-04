import Foundation
import KPModel
import KPSession
import LocalAuthentication
import Security

/// Biometric quick unlock: after a full unlock, the database key is kept
/// in the Keychain behind Face ID / Touch ID, on this device only, and
/// expires after the configured time. Changing the enrolled biometrics
/// invalidates it (`.biometryCurrentSet`), so a newly added face or
/// finger can't unlock the database.
enum QuickUnlock {
    private static let service = "dev.guilhermenl.keepassios.quick-unlock"

    private struct Stored: Codable {
        let password: Data?
        let keyFile: Data?
        let expires: Date
    }

    enum Failure: Error {
        case unavailable
        case cancelled
        case expired
        case notFound
    }

    /// Whether this device can use biometrics right now.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Face ID")
        case .touchID: return String(localized: "Touch ID")
        case .opticID: return String(localized: "Optic ID")
        default: return String(localized: "Biometrics")
        }
    }

    static func store(_ key: CompositeKey, for databaseID: UUID, validFor seconds: Int) throws {
        guard
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
        else { throw Failure.unavailable }
        let stored = Stored(
            password: key.password.map { Data($0.reveal().utf8) },
            keyFile: key.keyFileData,
            expires: Date().addingTimeInterval(TimeInterval(seconds))
        )
        let data = try JSONEncoder().encode(stored)
        remove(for: databaseID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: databaseID.uuidString,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unavailable }
    }

    /// Asks for biometrics and returns the stored key.
    static func retrieve(for databaseID: UUID, reason: String) async throws -> CompositeKey {
        let (status, data) = await copyItem(account: databaseID.uuidString, reason: reason)
        switch status {
        case errSecSuccess: break
        case errSecUserCanceled, errSecAuthFailed: throw Failure.cancelled
        case errSecItemNotFound: throw Failure.notFound
        default: throw Failure.unavailable
        }
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            throw Failure.notFound
        }
        guard stored.expires > Date() else {
            remove(for: databaseID)
            throw Failure.expired
        }
        return CompositeKey(
            password: stored.password.map { SecretString(bytes: Array($0)) },
            keyFileData: stored.keyFile
        )
    }

    /// Reads the Keychain item off the main actor: the call blocks until
    /// the biometric prompt is answered.
    @concurrent
    private nonisolated static func copyItem(account: String, reason: String) async -> (OSStatus, Data?) {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.guilhermenl.keepassios.quick-unlock",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    /// Whether a quick-unlock key is stored (without prompting).
    static func hasKey(for databaseID: UUID) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: databaseID.uuidString,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func remove(for databaseID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: databaseID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
