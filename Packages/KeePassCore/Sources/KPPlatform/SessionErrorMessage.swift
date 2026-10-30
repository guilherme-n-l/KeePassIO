#if canImport(Darwin)
    import Foundation
    import KPSession

    extension SessionError {
        /// What went wrong, for the person unlocking or saving.
        public var userMessage: String {
            switch self {
            case .invalidKey:
                String(localized: "The master password or key file is wrong.")
            case .unsupportedFormat(let detail):
                String(
                    localized:
                        "This database format isn't supported (\(detail)). Open it in KeePassXC and change Database Settings → Security → Encryption → Database format to KDBX 4."
                )
            case .corrupted:
                String(localized: "The file is damaged or isn't a KeePass database.")
            case .keyDerivationTooExpensive:
                String(
                    localized: "This database needs more memory to unlock than is available here. Open it in the app."
                )
            case .file(.notFound):
                String(localized: "The file can't be found. It may have been moved or deleted.")
            case .file(.accessDenied):
                String(localized: "The app no longer has permission to open this file. Remove it and add it again.")
            case .file, .other, .changedOnDisk:
                String(localized: "The file couldn't be read.")
            case .locked, .emptyKey, .edit:
                String(localized: "Something went wrong. Try again.")
            }
        }
    }
#endif
