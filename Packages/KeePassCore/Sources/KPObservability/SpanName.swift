/// Every traced operation in the app.
///
/// The raw value is the span's stable numeric ID. Linux probes and exported
/// traces identify spans by this number, so existing values must never be
/// reused or renumbered; add new cases with new numbers.
public enum SpanName: UInt32, CaseIterable, Sendable {
    // Unlock
    case unlockTotal = 1
    case kdfArgon2 = 2
    case kdfAES = 3
    case kdbxHeader = 4
    case kdbxDecrypt = 5
    case kdbxInflate = 6
    case kdbxXML = 7

    // Search
    case indexBuild = 20
    case searchQuery = 21

    // Merge
    case mergePlan = 30
    case mergeApply = 31

    // Save
    case saveSerialize = 40
    case saveEncrypt = 41
    case saveFsync = 42
    case saveReplace = 43

    // Quick create and extension sync
    case quickSheetShown = 50
    case quickUnlock = 51
    case quickSave = 52
    case syncPendingMerge = 53

    // AutoFill
    case autofillLaunch = 60
    case autofillUnlock = 61
    case autofillFirstResult = 62

    // App
    case appLaunch = 70
    case uiFirstFrame = 71

    /// Dotted name shown in Instruments, Perfetto and bpftrace output.
    public var displayName: String {
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
