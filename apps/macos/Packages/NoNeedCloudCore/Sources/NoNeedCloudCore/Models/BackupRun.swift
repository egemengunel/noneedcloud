import Foundation

/// The record of one finished (or stopped) backup run.
public struct BackupRun: Codable, Equatable, Identifiable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case succeeded
        /// Finished, but some items could not be copied (see `failedItems`).
        case completedWithErrors
        case failed
        case cancelled
    }

    public var id: UUID
    public var planID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: Outcome
    public var failureReason: String?
    /// Items present at the destination after this run, by source kind.
    public var protectedPhotos: Int
    public var protectedFiles: Int
    /// New or changed items written in this run.
    public var copiedItems: Int
    public var failedItems: Int
    public var bytesWritten: Int64

    public init(
        id: UUID = UUID(),
        planID: UUID,
        startedAt: Date,
        finishedAt: Date,
        outcome: Outcome,
        failureReason: String? = nil,
        protectedPhotos: Int = 0,
        protectedFiles: Int = 0,
        copiedItems: Int = 0,
        failedItems: Int = 0,
        bytesWritten: Int64 = 0
    ) {
        self.id = id
        self.planID = planID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failureReason = failureReason
        self.protectedPhotos = protectedPhotos
        self.protectedFiles = protectedFiles
        self.copiedItems = copiedItems
        self.failedItems = failedItems
        self.bytesWritten = bytesWritten
    }

    /// The run reached the end of its work list (with or without item errors).
    public var didComplete: Bool {
        outcome == .succeeded || outcome == .completedWithErrors
    }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}
