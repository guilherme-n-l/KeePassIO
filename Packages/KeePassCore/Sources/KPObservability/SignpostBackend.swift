#if canImport(os)
    import os
    import Synchronization

    /// Emits each span as an `OSSignposter` interval, visible in Instruments
    /// (Points of Interest and os_signpost) and `xctrace`, and measurable with
    /// `XCTOSSignpostMetric`. Signposts cost almost nothing when no tool is
    /// recording.
    public final class SignpostBackend: TraceBackend {
        public static let subsystem = "dev.guilhermenl.keepassios"

        private let signposter: OSSignposter
        private let open = Mutex<[UInt64: OSSignpostIntervalState]>([:])

        public init(category: String = OSLog.Category.pointsOfInterest.rawValue) {
            signposter = OSSignposter(subsystem: Self.subsystem, category: category)
        }

        public func begin(_ span: SpanName, id: UInt64, argument: UInt64) {
            let state = signposter.beginInterval(
                span.staticName,
                id: signposter.makeSignpostID(),
                "\(argument, privacy: .public)"
            )
            open.withLock { $0[id] = state }
        }

        public func end(_ span: SpanName, id: UInt64, argument: UInt64) {
            guard let state = open.withLock({ $0.removeValue(forKey: id) }) else { return }
            signposter.endInterval(span.staticName, state)
        }
    }

    extension SpanName {
        /// Signpost names must be static strings, so each case maps to a
        /// literal rather than reusing `displayName`.
        fileprivate var staticName: StaticString {
            switch self {
            case .unlockTotal: "unlock.total"
            case .kdfArgon2: "kdf.argon2"
            case .kdfAES: "kdf.aes"
            case .kdbxHeader: "kdbx.header"
            case .kdbxDecrypt: "kdbx.decrypt"
            case .kdbxInflate: "kdbx.inflate"
            case .kdbxXML: "kdbx.xml"
            case .indexBuild: "index.build"
            case .searchQuery: "search.query"
            case .mergePlan: "merge.plan"
            case .mergeApply: "merge.apply"
            case .saveSerialize: "save.serialize"
            case .saveEncrypt: "save.encrypt"
            case .saveFsync: "save.fsync"
            case .saveReplace: "save.replace"
            case .quickSheetShown: "quick.sheetShown"
            case .quickUnlock: "quick.unlock"
            case .quickSave: "quick.save"
            case .syncPendingMerge: "sync.pendingMerge"
            case .autofillLaunch: "autofill.launch"
            case .autofillUnlock: "autofill.unlock"
            case .autofillFirstResult: "autofill.firstResult"
            case .appLaunch: "app.launch"
            case .uiFirstFrame: "ui.firstFrame"
            }
        }
    }
#endif
