import Foundation

/// A stand-in engine that walks a fake work list through the real stage
/// pipeline without touching any files. Drives the UI until the real engine
/// lands (M2), and keeps UI tests deterministic afterwards.
public struct SimulatedBackupEngine: BackupEngine {
    public var photoCount: Int
    public var itemsPerFolder: Int
    public var enumerationDelay: Duration
    public var stageDelay: Duration
    /// Every Nth item fails with a readable reason; nil = never.
    public var failEvery: Int?
    public var estimator: ThroughputEstimator

    public init(
        photoCount: Int = 240,
        itemsPerFolder: Int = 80,
        enumerationDelay: Duration = .seconds(1.5),
        stageDelay: Duration = .milliseconds(25),
        failEvery: Int? = 97,
        estimator: ThroughputEstimator = ThroughputEstimator(window: 10, minimumElapsed: 3, minimumSpan: 2)
    ) {
        self.photoCount = photoCount
        self.itemsPerFolder = itemsPerFolder
        self.enumerationDelay = enumerationDelay
        self.stageDelay = stageDelay
        self.failEvery = failEvery
        self.estimator = estimator
    }

    struct WorkItem {
        var path: String
        var kind: BackupProgress.SourceKind
        var bytes: Int64
    }

    func workList(for plan: BackupPlan) -> [WorkItem] {
        var items: [WorkItem] = []
        if plan.photos.isEnabled {
            for i in 0..<photoCount {
                let day = 1 + i % 28, month = 1 + (i / 28) % 12, year = 2012 + i % 13
                let isVideo = plan.photos.includeVideos && i % 9 == 0
                let name = isVideo ? "IMG_\(4000 + i).MOV" : "IMG_\(4000 + i).HEIC"
                let path = String(format: "Photos/%04d/%02d/%02d/", year, month, day) + name
                items.append(WorkItem(path: path, kind: .photo, bytes: isVideo ? 48_000_000 : 3_200_000))
            }
        }
        if plan.files.isEnabled {
            for folder in plan.files.folders {
                for i in 0..<itemsPerFolder {
                    items.append(WorkItem(
                        path: "\(folder.displayName)/Document \(i + 1).pdf",
                        kind: .file,
                        bytes: 420_000
                    ))
                }
            }
        }
        return items
    }

    public func run(_ plan: BackupPlan) -> AsyncThrowingStream<BackupProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await simulate(plan, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func simulate(
        _ plan: BackupPlan,
        into continuation: AsyncThrowingStream<BackupProgress, any Error>.Continuation
    ) async throws {
        var progress = BackupProgress(phase: .enumerating, startedAt: Date())
        var estimator = self.estimator
        continuation.yield(progress)
        try await Task.sleep(for: enumerationDelay)

        let items = workList(for: plan)
        progress.phase = .copying
        progress.totalItems = items.count
        continuation.yield(progress)

        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let stages: [BackupProgress.Stage] = item.kind == .photo
                ? [.check, .fetch, .write]
                : [.check, .fetch, .write, .release]
            for stage in stages {
                progress.currentItem = .init(displayPath: item.path, stage: stage, kind: item.kind)
                continuation.yield(progress)
                try await Task.sleep(for: stageDelay)
            }

            if let failEvery, (index + 1) % failEvery == 0 {
                progress.failedItems += 1
            } else {
                progress.copiedItems += 1
                progress.bytesWritten += item.bytes
                switch item.kind {
                case .photo: progress.processedPhotos += 1
                case .file: progress.processedFiles += 1
                }
            }
            progress.processedItems += 1

            let now = Date()
            estimator.record(processed: progress.processedItems, at: now)
            progress.estimatedRemaining = estimator.estimateRemaining(progress.remainingItems ?? 0, now: now)
            continuation.yield(progress)
        }

        progress.phase = .finishing
        progress.currentItem = nil
        progress.estimatedRemaining = nil
        continuation.yield(progress)
        progress.phase = .finished
        continuation.yield(progress)
    }
}
