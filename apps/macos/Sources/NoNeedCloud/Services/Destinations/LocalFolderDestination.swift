import Foundation

/// Destination backed by a mounted volume: local disk, external drive, or
/// NAS share. Preserves the original CopyEngine folder behavior exactly.
final class LocalFolderDestination: BackupDestination {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var label: String { rootURL.path(percentEncoded: false) }

    func healthCheck() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw DestinationError("Destination path is not a folder: \(rootURL.path)")
            }
        } else {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        guard fileManager.isWritableFile(atPath: rootURL.path) else {
            throw DestinationError("Destination folder is not writable: \(rootURL.path)")
        }
    }

    func ensureDirectory(relPath: String) throws {
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(relPath),
            withIntermediateDirectories: true
        )
    }

    func copyFile(relPath: String, fromFile: URL, sourceModificationDate: Date, isCancelled: @escaping @Sendable () -> Bool) throws {
        let destinationFile = rootURL.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: destinationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let input = try FileHandle(forReadingFrom: fromFile)
        defer { try? input.close() }
        let temporaryURL = URL(fileURLWithPath: destinationFile.path + ".tmp")
        do {
            guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw CopyError.temporaryFileCreationFailed(path: temporaryURL.path)
            }
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { try? output.close() }
            while true {
                if isCancelled() { throw CopyError.cancelled }
                guard let chunk = try input.read(upToCount: CopyEngine.chunkSize), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
            if FileManager.default.fileExists(atPath: destinationFile.path) {
                _ = try FileManager.default.replaceItemAt(destinationFile, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationFile)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        try FileManager.default.setAttributes(
            [.modificationDate: sourceModificationDate],
            ofItemAtPath: destinationFile.path
        )
    }

    func destinationFileExists(relPath: String) -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(relPath).path)
    }
}
