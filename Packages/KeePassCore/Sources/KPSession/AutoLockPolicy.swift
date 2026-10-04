import Foundation

/// Decides when an unlocked database must lock again.
public struct AutoLockPolicy: Sendable, Equatable {
    /// Lock after this long without user activity, or this long in the
    /// background. Zero locks immediately when the app leaves the
    /// foreground.
    public var timeout: TimeInterval

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    public func shouldLock(lastActivity: Date, backgroundedAt: Date?, now: Date) -> Bool {
        if let backgroundedAt {
            return timeout == 0 || now.timeIntervalSince(backgroundedAt) >= timeout
        }
        return timeout > 0 && now.timeIntervalSince(lastActivity) >= timeout
    }
}
