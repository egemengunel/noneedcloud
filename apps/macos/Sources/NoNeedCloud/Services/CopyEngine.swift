import Combine
import Foundation

struct BackupFileError: Equatable, Sendable {
    var path: String
    var reason: String
}

struct CopyRunResult: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case completed
        case cancelled
    }

    var outcome: Outcome
    var filesCopied: Int
    var filesSkipped: Int
    var filesFailed: Int
    var bytesCopied: Int64
    var itemsProtected: Int
}

@MainActor
final class CopyEngineState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var wasCancelled = false
    @Published private(set) var percent: Double = 0
    @Published private(set) var currentFile: String?
    @Published private(set) var itemsCopied = 0
    @Published private(set) var itemsSkipped = 0
    @Published private(set) var itemsTotal = 0
    @Published private(set) var bytesCopied: Int64 = 0
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
        wasCancelled = false
        self.itemsTotal = itemsTotal
        self.bytesTotal = bytesTotal
        self.startedAt = startedAt
    }

    func report(currentFile: String, itemsCopied: Int, itemsSkipped: Int, bytesCopied: Int64) {
        self.currentFile = currentFile
        self.itemsCopied = itemsCopied
        self.itemsSkipped = itemsSkipped
        self.bytesCopied = bytesCopied
        percent = bytesTotal > 0 ? Double(bytesCopied) / Double(bytesTotal) : 0
    }

    func recordError(_ error: BackupFileError) {
        errors.append(error)
    }

    func finish(cancelled: Bool) {
        isRunning = false
        wasCancelled = cancelled
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

final class CopyEngine: Sendable {
    static let chunkSize = 1 << 20

    let state: CopyEngineState
    private let sourceURL: URL
    private let destinationURL: URL
    private let stateURL: URL
    private let cancelFlag = CancellationFlag()
    private let perFileDelayNanos: UInt64

    init(
        sourceURL: URL,
        destinationURL: URL,
        stateURL: URL,
        perFileDelayNanos: UInt64 = 0
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.stateURL = stateURL
        self.perFileDelayNanos = perFileDelayNanos
        self.state = CopyEngineState()
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
        var lastPublish = Date.distantPast

        func publishIfDue(currentFile: String, force: Bool = false) async {
            let now = Date()
            guard force || now.timeIntervalSince(lastPublish) >= 0.1 else { return }
            lastPublish = now
            await state.report(
                currentFile: currentFile,
                itemsCopied: copied,
                itemsSkipped: skipped,
                bytesCopied: bytesCopied
            )
        }

        let scan = Self.scanTree(at: sourceURL)
        await MainActor.run {
            state.begin(itemsTotal: scan.files.count, bytesTotal: scan.totalBytes, startedAt: startedAt)
        }

        for relativeDirectory in scan.directories {
            let destinationDirectory = destinationURL.appendingPathComponent(relativeDirectory)
            do {
                try FileManager.default.createDirectory(
                    at: destinationDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                failed += 1
                await state.recordError(BackupFileError(path: relativeDirectory, reason: error.localizedDescription))
            }
        }

        for file in scan.files {
            if cancelFlag.isCancelled { break }
            if perFileDelayNanos > 0 {
                try? await Task.sleep(nanoseconds: perFileDelayNanos)
                if cancelFlag.isCancelled { break }
            }
            let destinationFile = destinationURL.appendingPathComponent(file.relativePath)
            if let known = index.entry(for: file.relativePath),
               known.size == file.size,
               known.mtime == file.mtime.timeIntervalSince1970 {
                skipped += 1
                await publishIfDue(currentFile: file.relativePath, force: true)
                continue
            }
            do {
                try Self.copyFile(
                    from: sourceURL.appendingPathComponent(file.relativePath),
                    to: destinationFile,
                    sourceModificationDate: file.mtime,
                    chunkSize: Self.chunkSize,
                    cancelFlag: cancelFlag
                )
                index.update(file.relativePath, size: file.size, mtime: file.mtime.timeIntervalSince1970)
                copied += 1
                bytesCopied += file.size
                await publishIfDue(currentFile: file.relativePath, force: true)
                if copied % 200 == 0 {
                    try? index.save()
                }
            } catch CopyError.cancelled {
                try? FileManager.default.removeItem(at: destinationFile)
                try? index.save()
                await state.finish(cancelled: true)
                return CopyRunResult(
                    outcome: .cancelled,
                    filesCopied: copied,
                    filesSkipped: skipped,
                    filesFailed: failed,
                    bytesCopied: bytesCopied,
                    itemsProtected: index.count
                )
            } catch {
                try? FileManager.default.removeItem(at: destinationFile)
                failed += 1
                await state.recordError(BackupFileError(path: file.relativePath, reason: error.localizedDescription))
            }
        }

        try? index.save()
        let cancelled = cancelFlag.isCancelled
        await MainActor.run {
            state.finish(cancelled: cancelled)
        }
        return CopyRunResult(
            outcome: cancelled ? .cancelled : .completed,
            filesCopied: copied,
            filesSkipped: skipped,
            filesFailed: failed,
            bytesCopied: bytesCopied,
            itemsProtected: index.count
        )
    }

    private enum CopyError: Error {
        case cancelled
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

    private static func scanTree(at sourceURL: URL) -> ScanResult {
        let fileManager = FileManager.default
        var directories: [String] = []
        var files: [ScannedFile] = []
        var totalBytes: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ) else {
            return ScanResult(directories: [], files: [], totalBytes: 0)
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

    private static func copyFile(
        from source: URL,
        to destination: URL,
        sourceModificationDate: Date,
        chunkSize: Int,
        cancelFlag: CancellationFlag
    ) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        while true {
            if cancelFlag.isCancelled { throw CopyError.cancelled }
            guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: sourceModificationDate],
            ofItemAtPath: destination.path
        )
    }
}
