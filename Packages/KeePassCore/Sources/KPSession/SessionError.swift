import KPModel

public enum SessionError: Error, Equatable, Sendable {
    case locked
    case emptyKey
    case invalidKey
    case unsupportedFormat(String)
    case corrupted(String)
    case keyDerivationTooExpensive(memoryBytes: UInt64)
    case changedOnDisk(FileVersion)
    case file(FileError)
    case edit(EditError)
    case other(String)

    init(_ error: any Error) {
        switch error {
        case let error as SessionError: self = error
        case let error as FileError: self = .file(error)
        case let error as EditError: self = .edit(error)
        case let error as CodecError:
            switch error {
            case .invalidKey: self = .invalidKey
            case .unsupportedFormat(let detail): self = .unsupportedFormat(detail)
            case .corrupted(let detail): self = .corrupted(detail)
            case .keyDerivationTooExpensive(let memory): self = .keyDerivationTooExpensive(memoryBytes: memory)
            }
        default: self = .other(String(describing: type(of: error)))
        }
    }
}

extension SessionError {
    /// Whether the database's file couldn't be reached at all: missing,
    /// no longer permitted, or failing to read or write. Nothing is wrong
    /// with the database itself, so a copy kept elsewhere is still good.
    public var isUnreachableFile: Bool {
        switch self {
        case .file(.notFound), .file(.accessDenied), .file(.ioFailure): true
        default: false
        }
    }
}
