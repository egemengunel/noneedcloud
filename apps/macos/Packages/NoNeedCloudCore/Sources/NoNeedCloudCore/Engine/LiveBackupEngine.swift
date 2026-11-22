import Foundation

/// The real engine. Runs the Photos coordinator and one incremental
/// `CopyEngine` per source folder (ported from `feature/macos-app-shell`)
/// against the plan's destination folder, and turns their progress into
/// `BackupProgress` updates.
///
/// Layout at the destination: `Photos/YYYY/MM/DD/…` for the library, and one
/// top-level folder per source folder (named after it).
public struct LiveBackupEngine: BackupEngine {
    let stateDirectory: URL
    let photoSource: @Sendable () -> any PhotoLibrarySource
    let estimator: ThroughputEstimator

    public init(stateDirectory: URL? = nil) {
        self.init(
            stateDirectory: stateDirectory ?? Self.defaultStateDirectory,
            photoSource: { PhotosFrameworkSource() }
        )
    }

    init(
        stateDirectory: URL,
        photoSource: @escaping @Sendable () -> any PhotoLibrarySource,
        estimator: ThroughputEstimator = ThroughputEstimator(window: 30, minimumElapsed: 5, minimumSpan: 3)
    ) {
        self.stateDirectory = stateDirectory
        self.photoSource = photoSource
        self.estimator = estimator
    }

    /// Where the incremental indexes live (what has already been copied where).
    public static var defaultStateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoNeedCloud/RunState", isDirectory: true)
    }

    public func run(_ plan: BackupPlan) -> AsyncThrowingStream<BackupProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let run = LiveRun(engine: self, continuation: continuation)
                do {
                    try await run.perform(plan)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum LiveBackupError: LocalizedError, Equatable {
    case noDestination
    case destinationUnavailable

    public var errorDescription: String? {
        switch self {
        case .noDestination:
            String(localized: "Choose where to save your backup first.")
        case .destinationUnavailable:
            String(localized: "The backup destination can't be reached.")
        }
    }
}

/// One run of `LiveBackupEngine`. Main-actor isolated because engine state
/// callbacks arrive on the main actor; the copying itself runs off it.
@MainActor
private final class LiveRun {
    typealias Continuation = AsyncThrowingStream<BackupProgress, any Error>.Continuation

    private let engine: LiveBackupEngine
    private let continuation: Continuation
    private var progress: BackupProgress
    private var estimator: ThroughputEstimator

    /// Totals from stages that already finished.
    private var base = Counters()
    /// Pre-counted files of folder stages still to come.
    private var pendingItems = 0
    /// False while the Photos stage hasn't worked out its total yet.
    private var totalsKnown = true

    private struct Counters {
        var processed = 0, copied = 0, failed = 0, photos = 0, files = 0
        var bytes: Int64 = 0
        var missed: [MissedItem] = []
    }

    private struct Stage {
        var kind: BackupProgress.SourceKind
        var scope: String
        var location: String
        /// `begin` calls before the stage's totals are real (see `CopyEngineState.beginCount`).
        var beginsUntilTotals: Int
    }

    init(engine: LiveBackupEngine, continuation: Continuation) {
        self.engine = engine
        self.continuation = continuation
        self.progress = BackupProgress(phase: .enumerating, startedAt: Date())
        self.estimator = engine.estimator
    }

    func perform(_ plan: BackupPlan) async throws {
        continuation.yield(progress)

        guard let destination = plan.destination else { throw LiveBackupError.noDestination }
        guard let destinationURL = try? destination.resolve().url else { throw LiveBackupError.destinationUnavailable }
        let destinationAccess = destinationURL.startAccessingSecurityScopedResource()
        defer { if destinationAccess { destinationURL.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LiveBackupError.destinationUnavailable
        }

        // Open every source folder up front so a lost one shows as missed, not as a failed run.
        var folders: [(reference: FolderReference, url: URL, scope: String)] = []
        var usedScopes: Set<String> = ["photos"]
        defer { for folder in folders { folder.url.stopAccessingSecurityScopedResource() } }
        if plan.files.isEnabled {
            for reference in plan.files.folders {
                guard let url = try? reference.resolve().url else {
                    base.failed += 1
                    base.processed += 1
                    base.missed.append(MissedItem(
                        name: reference.displayName,
                        location: reference.displayName,
                        reason: String(localized: "NoNeedCloud lost access to this folder. Add it again in Sources.")
                    ))
                    continue
                }
                _ = url.startAccessingSecurityScopedResource()
                folders.append((reference, url, Self.uniqueScope(reference.displayName, used: &usedScopes)))
            }
        }

        let counts = await Self.countFiles(in: folders.map(\.url))
        pendingItems = counts.reduce(0, +)

        let backsUpPhotos = plan.photos.isEnabled && (plan.photos.includePhotos || plan.photos.includeVideos)
        if backsUpPhotos {
            totalsKnown = false
            let coordinator = PhotoBackupCoordinator(
                source: engine.photoSource(),
                destinationURL: destinationURL,
                options: PhotoOptions(
                    photosOnly: plan.photos.includePhotos && !plan.photos.includeVideos,
                    videosOnly: plan.photos.includeVideos && !plan.photos.includePhotos,
                    includeEdits: plan.photos.includeEdits,
                    includeSharedAlbums: plan.photos.includeSharedAlbums
                ),
                stateURL: PhotoIncrementalIndex.indexFileURL(stateDirectory: engine.stateDirectory, destination: destinationURL)
            )
            let stage = Stage(kind: .photo, scope: "Photos", location: String(localized: "iCloud Photos"), beginsUntilTotals: 2)
            coordinator.state.onChange = { [weak self] state in self?.update(from: state, stage: stage) }
            _ = await withTaskCancellationHandler {
                await coordinator.run()
            } onCancel: {
                coordinator.stop()
            }
            commit(coordinator.state, stage: stage)
            totalsKnown = true
            if Task.isCancelled { return }
        }

        for (index, folder) in folders.enumerated() {
            pendingItems -= counts[index]
            let copier = CopyEngine(
                sourceURL: folder.url,
                destination: LocalFolderDestination(rootURL: destinationURL),
                destinationScope: folder.scope,
                stateURL: IncrementalIndex.indexFileURL(
                    stateDirectory: engine.stateDirectory,
                    destination: .folder(destinationURL),
                    source: .folder(folder.url)
                ),
                ubiquitousSource: ICloudDriveSource()
            )
            let stage = Stage(kind: .file, scope: folder.scope, location: folder.reference.displayName, beginsUntilTotals: 1)
            copier.state.onChange = { [weak self] state in self?.update(from: state, stage: stage) }
            _ = await withTaskCancellationHandler {
                await copier.run()
            } onCancel: {
                copier.stop()
            }
            commit(copier.state, stage: stage)
            if Task.isCancelled { return }
        }

        progress.phase = .finishing
        progress.currentItem = nil
        progress.estimatedRemaining = nil
        progress.totalItems = max(progress.totalItems ?? 0, progress.processedItems)
        continuation.yield(progress)
        progress.phase = .finished
        continuation.yield(progress)
    }

    // MARK: - Progress

    private func counters(for state: CopyEngineState, stage: Stage) -> Counters {
        var counters = base
        let failed = state.errors.count
        counters.processed += state.itemsCopied + state.itemsSkipped + failed
        counters.copied += state.itemsCopied
        counters.failed += failed
        switch stage.kind {
        case .photo: counters.photos += state.itemsCopied + state.itemsSkipped
        case .file: counters.files += state.itemsCopied + state.itemsSkipped
        }
        counters.bytes += state.bytesCopied
        counters.missed += state.errors.map { missedItem($0, stage: stage) }
        return counters
    }

    private func update(from state: CopyEngineState, stage: Stage) {
        let counters = counters(for: state, stage: stage)
        apply(counters)

        let stageTotalKnown = state.beginCount >= stage.beginsUntilTotals
        if stage.kind == .photo, stageTotalKnown { totalsKnown = true }
        if totalsKnown {
            let stageRemaining = stageTotalKnown ? max(0, state.itemsTotal - state.itemsCopied - state.itemsSkipped) : 0
            progress.totalItems = counters.processed + stageRemaining + pendingItems
            progress.phase = .copying
        } else {
            progress.totalItems = nil
            progress.phase = .enumerating
        }

        if let file = state.currentFile, !file.isEmpty {
            progress.currentItem = .init(
                displayPath: "\(stage.scope)/\(file)",
                stage: stage.kind == .photo ? .fetch : .write,
                kind: stage.kind
            )
        }

        let now = Date()
        estimator.record(processed: progress.processedItems, at: now)
        progress.estimatedRemaining = progress.remainingItems.flatMap { estimator.estimateRemaining($0, now: now) }
        continuation.yield(progress)
    }

    private func commit(_ state: CopyEngineState, stage: Stage) {
        state.onChange = nil
        base = counters(for: state, stage: stage)
        apply(base)
    }

    private func apply(_ counters: Counters) {
        progress.processedItems = counters.processed
        progress.copiedItems = counters.copied
        progress.failedItems = counters.failed
        progress.processedPhotos = counters.photos
        progress.processedFiles = counters.files
        progress.bytesWritten = counters.bytes
        progress.missedItems = counters.missed
    }

    private func missedItem(_ error: BackupFileError, stage: Stage) -> MissedItem {
        let path = error.path as NSString
        let folder = path.deletingLastPathComponent
        let location = stage.kind == .file && !folder.isEmpty && !folder.hasPrefix("/")
            ? "\(stage.location) / \(folder)"
            : stage.location
        return MissedItem(name: path.lastPathComponent, location: location, reason: error.reason)
    }

    // MARK: - Helpers

    private static func uniqueScope(_ name: String, used: inout Set<String>) -> String {
        var candidate = name.isEmpty ? "Folder" : name
        var suffix = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(name) \(suffix)"
            suffix += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }

    /// Counts regular files under each folder so the overall total is known
    /// before the folder stages start.
    nonisolated private static func countFiles(in urls: [URL]) async -> [Int] {
        urls.map { url in
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { return 0 }
            var count = 0
            for case let file as URL in enumerator
            where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
            return count
        }
    }
}
