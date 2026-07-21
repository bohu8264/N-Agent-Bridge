import Foundation

/// NuPhy's S4 management interface does not attach a transaction identifier
/// to replies. If two IOHID sessions issue commands at the same time, both
/// callbacks can observe the same response and one operation may time out or
/// accept a reply that belongs to the other operation. This happened most
/// often during first-run keymap setup while lighting discovery was active.
///
/// Keep every management frame process-wide serial. Higher-level operations
/// still retain their existing read/backup/write/readback/rollback behavior;
/// this lock only prevents their individual protocol frames from colliding.
enum NuPhyHIDOperationCoordinator {
    private static let lock = NSLock()

    static func withExclusiveAccess<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
