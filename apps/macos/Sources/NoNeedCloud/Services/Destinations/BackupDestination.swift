import Foundation

struct DestinationError: LocalizedError, Sendable {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// A backup target. The CopyEngine performs every destination mutation
/// (directories, atomic file copies, partial cleanup) through this protocol,
/// so local folders, S3 buckets, and cloud drives share one incremental loop.
protocol BackupDestination: AnyObject, Sendable {
    var label: String { get }

    /// Pre-flight check that the destination is reachable and authenticated.
    /// A thrown error fails the run before any file is copied.
    func healthCheck() async throws

    /// Ensures the directory structure for a relative directory path exists.
    func ensureDirectory(relPath: String) async throws

    /// Copies the local file at `fromFile` to `relPath` atomically: a failed
    /// copy must never leave a partial object that looks complete. Long
    /// copies poll `isCancelled` so a stopped run ends promptly.
    func copyFile(
        relPath: String,
        fromFile: URL,
        sourceModificationDate: Date,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws

    /// Whether a complete copy of `relPath` exists at the destination.
    /// Used after a failed copy to decide whether the incremental entry,
    /// which still describes the last fully copied version, can be kept.
    func destinationFileExists(relPath: String) -> Bool

    /// Whether the destination can cheaply move an existing copy into the
    /// Deleted folder (local folders can; cloud object stores would need an
    /// expensive download-then-reupload).
    var supportsMirroring: Bool { get }

    /// Moves the destination copy at `relPath` to `deletedRelPath`
    /// (`Deleted/<date>/<original relPath>`). A missing source copy counts as
    /// already gone, so the move is idempotent.
    func moveToDeleted(relPath: String, deletedRelPath: String) async throws

    /// Top-level folder names inside the Deleted root, for retention purging.
    func deletedFolderNames(rootRelPath: String) async throws -> [String]

    /// Removes one Deleted date folder (`relPath` includes the Deleted root).
    func purgeDeletedFolder(relPath: String) async throws
}

extension BackupDestination {
    var supportsMirroring: Bool { false }

    func moveToDeleted(relPath: String, deletedRelPath: String) async throws {
        throw DestinationError("Mirroring is not supported by this destination.")
    }

    func deletedFolderNames(rootRelPath: String) async throws -> [String] { [] }

    func purgeDeletedFolder(relPath: String) async throws {
        throw DestinationError("Mirroring is not supported by this destination.")
    }
}
