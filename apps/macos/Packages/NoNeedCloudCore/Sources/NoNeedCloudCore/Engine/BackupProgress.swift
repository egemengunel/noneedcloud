import Foundation

/// The single observable progress value the UI binds to (UX spec §5.2).
/// The UI never computes progress itself.
public struct BackupProgress: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case enumerating, copying, finishing, cancelled, finished
    }

    public enum Stage: String, Sendable {
        case check, fetch, write, release
    }

    public enum SourceKind: String, Sendable {
        case photo, file
    }

    public struct CurrentItem: Equatable, Sendable {
        public var displayPath: String
        public var stage: Stage
        public var kind: SourceKind

        public init(displayPath: String, stage: Stage, kind: SourceKind) {
            self.displayPath = displayPath
            self.stage = stage
            self.kind = kind
        }
    }

    public var phase: Phase
    /// nil while enumerating.
    public var totalItems: Int?
    /// checked + copied + skipped + failed.
    public var processedItems: Int
    public var copiedItems: Int
    public var failedItems: Int
    public var processedPhotos: Int
    public var processedFiles: Int
    public var bytesWritten: Int64
    /// Files that couldn't be copied so far in this run.
    public var missedItems: [MissedItem]
    public var currentItem: CurrentItem?
    public var startedAt: Date
    public var estimatedRemaining: TimeInterval?

    public init(
        phase: Phase = .enumerating,
        totalItems: Int? = nil,
        processedItems: Int = 0,
        copiedItems: Int = 0,
        failedItems: Int = 0,
        processedPhotos: Int = 0,
        processedFiles: Int = 0,
        bytesWritten: Int64 = 0,
        missedItems: [MissedItem] = [],
        currentItem: CurrentItem? = nil,
        startedAt: Date,
        estimatedRemaining: TimeInterval? = nil
    ) {
        self.phase = phase
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.copiedItems = copiedItems
        self.failedItems = failedItems
        self.processedPhotos = processedPhotos
        self.processedFiles = processedFiles
        self.bytesWritten = bytesWritten
        self.missedItems = missedItems
        self.currentItem = currentItem
        self.startedAt = startedAt
        self.estimatedRemaining = estimatedRemaining
    }

    /// 0…1, or nil while the total is unknown (show an indeterminate bar).
    public var fractionCompleted: Double? {
        guard let totalItems else { return nil }
        guard totalItems > 0 else { return 1 }
        return min(1, Double(processedItems) / Double(totalItems))
    }

    public var remainingItems: Int? {
        totalItems.map { max(0, $0 - processedItems) }
    }
}
