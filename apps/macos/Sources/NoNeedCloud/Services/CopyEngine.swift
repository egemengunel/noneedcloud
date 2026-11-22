import Combine
import Foundation

struct BackupFileError: Codable, Equatable, Sendable {
    var path: String
    var reason: String
}

struct CopyRunResult: Equatable, Sendable {
    enum Outcome: Codable, Equatable, Sendable {
        case completed
        case cancelled
        case failed
    }

    var outcome: Outcome
    var itemsCopied: Int
    var itemsSkipped: Int
    var itemsFailed: Int
    var bytesCopied: Int64
    var itemsProtected: Int
}

@MainActor
final class CopyEngineState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var percent: Double = 0
    @Published private(set) var currentFile: String?
    @Published private(set) var itemsCopied = 0
    @Published private(set) var itemsSkipped = 0
    @Published private(set) var itemsTotal = 0
    @Published private(set) var bytesCopied: Int64 = 0
    @Published private(set) var bytesSkipped: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var errors: [BackupFileError] = []

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    nonisolated init() {
    }

    func begin(itemsTotal: Int, bytesTotal: Int64, startedAt: Date) {
        isRunning = true
        self.itemsTotal = itemsTotal
        self.bytesTotal = bytesTotal
        self.startedAt = startedAt
    }

    func report(currentFile: String, itemsCopied: Int, itemsSkipped: Int, bytesCopied: Int64, bytesSkipped: Int64) {
        self.currentFile = currentFile
        self.itemsCopied = itemsCopied
        self.itemsSkipped = itemsSkipped
        self.bytesCopied = bytesCopied
        self.bytesSkipped = bytesSkipped
        let processed = bytesCopied + bytesSkipped
        percent = bytesTotal > 0 ? Double(processed) / Double(bytesTotal) : 0
    }

    func recordError(_ error: BackupFileError) {
        errors.append(error)
    }

    func finish(cancelled: Bool) {
        isRunning = false
        currentFile = nil
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

enum CopyError: LocalizedError {
    case cancelled
    case temporaryFileCreationFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Copy cancelled."
        case .temporaryFileCreationFailed(let path):
            return "Could not create temporary copy file at \(path)."
        }
    }
}

final class CopyEngine: Sendable {
    static let chunkSize = 1 << 20

    let state: CopyEngineState
    private let sourceURL: URL
    private let destination: any BackupDestination
    private let destinationScope: String
    private let stateURL: URL
    private let cancelFlag = CancellationFlag()
    private let perFileDelayNanos: UInt64
    private let ubiquitousSource: (any UbiquitousFileSource)?

    init(
        sourceURL: URL,
        destination: any BackupDestination,
        destinationScope: String = "",
        stateURL: URL,
        perFileDelayNanos: UInt64 = 0,
        ubiquitousSource: (any UbiquitousFileSource)? = nil
    ) {
        self.sourceURL = sourceURL
        self.destination = destination
        self.destinationScope = destinationScope
        self.stateURL = stateURL
        self.perFileDelayNanos = perFileDelayNanos
        self.ubiquitousSource = ubiquitousSource
        self.state = CopyEngineState()
    }

    convenience init(
        sourceURL: URL,
        destinationURL: URL,
        stateURL: URL,
        perFileDelayNanos: UInt64 = 0,
        ubiquitousSource: (any UbiquitousFileSource)? = nil
    ) {
        self.init(
            sourceURL: sourceURL,
            destination: LocalFolderDestination(rootURL: destinationURL),
            stateURL: stateURL,
            perFileDelayNanos: perFileDelayNanos,
            ubiquitousSource: ubiquitousSource
        )
    }

    private func destinationRelPath(_ relativePath: String) -> String {
        destinationScope.isEmpty ? relativePath : destinationScope + "/" + relativePath
    }

    nonisolated func stop() {
        cancelFlag.cancel()
    }

    func run() async -> CopyRunResult {
        let startedAt = Date()
        let index = IncrementalIndex(url: stateURL)
        var copied = 0
        var skipped = 0
        var failed = 0
        var bytesCopied: Int64 = 0
        var bytesSkipped: Int64 = 0
        var lastPublish = Date.distantPast

        func publishIfDue(currentFile: String, force: Bool = false) async {
            let now = Date()
            guard force || now.timeIntervalSince(lastPublish) >= 0.1 else { return }
            lastPublish = now
            await state.report(
                currentFile: currentFile,
                itemsCopied: copied,
                itemsSkipped: skipped,
                bytesCopied: bytesCopied,
                bytesSkipped: bytesSkipped
            )
        }

        func sourceFailureResult(reason: String) async -> CopyRunResult {
            failed += 1
            await state.begin(itemsTotal: 0, bytesTotal: 0, startedAt: startedAt)
            await state.recordError(BackupFileError(path: sourceURL.path, reason: reason))
            await state.finish(cancelled: false)
            return CopyRunResult(
                outcome: .failed,
                itemsCopied: copied,
                itemsSkipped: skipped,
                itemsFailed: failed,
                bytesCopied: bytesCopied,
                itemsProtected: index.count
            )
        }

        func destinationFailureResult(reason: String) async -> CopyRunResult {
            failed += 1
            await state.begin(itemsTotal: 0, bytesTotal: 0, startedAt: startedAt)
            await state.recordError(BackupFileError(path: destination.label, reason: reason))
            await state.finish(cancelled: false)
            return CopyRunResult(
                outcome: .failed,
                itemsCopied: copied,
                itemsSkipped: skipped,
                itemsFailed: failed,
                bytesCopied: bytesCopied,
                itemsProtected: index.count
            )
        }

        if let reason = Self.sourceAccessibilityError(at: sourceURL) {
            return await sourceFailureResult(reason: reason)
        }

        do {
            try await destination.healthCheck()
        } catch {
            return await destinationFailureResult(reason: "Destination not ready — \(error.localizedDescription)")
        }

        guard let scan = Self.scanTree(at: sourceURL) else {
            return await sourceFailureResult(reason: "Source directory could not be read.")
        }

        await state.begin(itemsTotal: scan.files.count, bytesTotal: scan.totalBytes, startedAt: startedAt)

        for relativeDirectory in scan.directories {
            do {
                try await destination.ensureDirectory(relPath: destinationRelPath(relativeDirectory))
            } catch {
                failed += 1
                await state.recordError(BackupFileError(path: relativeDirectory, reason: error.localizedDescription))
            }
        }

        var lastFile = ""
        for file in scan.files {
            if cancelFlag.isCancelled { break }
            if perFileDelayNanos > 0 {
                try? await Task.sleep(nanoseconds: perFileDelayNanos)
                if cancelFlag.isCancelled { break }
            }
            lastFile = file.relativePath
            let destinationRel = destinationRelPath(file.relativePath)
            if let known = index.entry(for: file.relativePath),
               known.size == file.size,
               known.mtime == file.mtime.timeIntervalSince1970 {
                skipped += 1
                bytesSkipped += file.size
                await publishIfDue(currentFile: file.relativePath)
                continue
            }
            let fileURL = sourceURL.appendingPathComponent(file.relativePath)
            let offloadOutcome = await SmartOffload.run(
                for: fileURL,
                source: ubiquitousSource,
                isCancelled: { [cancelFlag] in cancelFlag.isCancelled }
            ) {
                try await destination.copyFile(
                    relPath: destinationRel,
                    fromFile: fileURL,
                    sourceModificationDate: file.mtime,
                    isCancelled: { [cancelFlag] in cancelFlag.isCancelled }
                )
            }
            switch offloadOutcome {
            case .copied:
                index.update(file.relativePath, size: file.size, mtime: file.mtime.timeIntervalSince1970)
                copied += 1
                bytesCopied += file.size
                await publishIfDue(currentFile: file.relativePath, force: true)
                if copied % 200 == 0 {
                    try? index.save()
                }
            case .fetchFailed(let error):
                if error is CancellationError {
                    try? index.save()
                    await state.finish(cancelled: true)
                    return CopyRunResult(
                        outcome: .cancelled,
                        itemsCopied: copied,
                        itemsSkipped: skipped,
                        itemsFailed: failed,
                        bytesCopied: bytesCopied,
                        itemsProtected: index.count
                    )
                }
                failed += 1
                await state.recordError(BackupFileError(path: file.relativePath, reason: error.localizedDescription))
            case .copyFailed(let error):
                if let copyError = error as? CopyError, case .cancelled = copyError {
                    if !destination.destinationFileExists(relPath: destinationRel) {
                        index.remove(file.relativePath)
                    }
                    try? index.save()
                    await state.finish(cancelled: true)
                    return CopyRunResult(
                        outcome: .cancelled,
                        itemsCopied: copied,
                        itemsSkipped: skipped,
                        itemsFailed: failed,
                        bytesCopied: bytesCopied,
                        itemsProtected: index.count
                    )
                }
                if !destination.destinationFileExists(relPath: destinationRel) {
                    index.remove(file.relativePath)
                }
                failed += 1
                await state.recordError(BackupFileError(path: file.relativePath, reason: error.localizedDescription))
            }
        }

        await publishIfDue(currentFile: lastFile, force: true)
        try? index.save()
        let cancelled = cancelFlag.isCancelled
        await state.finish(cancelled: cancelled)
        return CopyRunResult(
            outcome: cancelled ? .cancelled : .completed,
            itemsCopied: copied,
            itemsSkipped: skipped,
            itemsFailed: failed,
            bytesCopied: bytesCopied,
            itemsProtected: index.count
        )
    }

    private struct ScannedFile: Sendable {
        var relativePath: String
        var size: Int64
        var mtime: Date
    }

    private struct ScanResult: Sendable {
        var directories: [String]
        var files: [ScannedFile]
        var totalBytes: Int64
    }

    private static func sourceAccessibilityError(at sourceURL: URL) -> String? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            return "Source directory does not exist."
        }
        guard isDirectory.boolValue else {
            return "Source path is not a directory."
        }
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            return "Source directory is not readable."
        }
        return nil
    }

    private static func scanTree(at sourceURL: URL) -> ScanResult? {
        let fileManager = FileManager.default
        var directories: [String] = []
        var files: [ScannedFile] = []
        var totalBytes: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ) else {
            return nil
        }
        let rootPath = sourceURL.resolvingSymlinksInPath().path
        for case let url as URL in enumerator {
            let rawPath = url.path
            let resolvedPath = rawPath.hasPrefix(rootPath) ? rawPath : url.resolvingSymlinksInPath().path
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let values = try? url.resourceValues(forKeys: keys)
            guard let values else { continue }
            if values.isDirectory == true {
                if resolvedPath != rootPath {
                    directories.append(String(resolvedPath.dropFirst(rootPath.count + 1)))
                }
                continue
            }
            guard let size = values.fileSize, let mtime = values.contentModificationDate else { continue }
            files.append(ScannedFile(
                relativePath: String(resolvedPath.dropFirst(rootPath.count + 1)),
                size: Int64(size),
                mtime: mtime
            ))
            totalBytes += Int64(size)
        }
        return ScanResult(
            directories: directories.sorted(),
            files: files.sorted { $0.relativePath < $1.relativePath },
            totalBytes: totalBytes
        )
    }
}
