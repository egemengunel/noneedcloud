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

    /// What started the run.
    public enum Trigger: String, Codable, Sendable {
        case manual, scheduled
    }

    public var id: UUID
    public var planID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: Outcome
    public var trigger: Trigger
    public var failureReason: String?
    /// Items present at the destination after this run, by source kind.
    public var protectedPhotos: Int
    public var protectedFiles: Int
    /// New or changed items written in this run.
    /// Items looked at in this run (copied + unchanged + failed).
    public var processedItems: Int
    public var copiedItems: Int
    public var failedItems: Int
    public var bytesWritten: Int64
    /// The files that couldn't be copied, with reasons.
    public var missedItems: [MissedItem]

    public init(
        id: UUID = UUID(),
        planID: UUID,
        startedAt: Date,
        finishedAt: Date,
        outcome: Outcome,
        trigger: Trigger = .manual,
        failureReason: String? = nil,
        protectedPhotos: Int = 0,
        protectedFiles: Int = 0,
        processedItems: Int? = nil,
        copiedItems: Int = 0,
        failedItems: Int = 0,
        bytesWritten: Int64 = 0,
        missedItems: [MissedItem] = []
    ) {
        self.id = id
        self.planID = planID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.trigger = trigger
        self.failureReason = failureReason
        self.protectedPhotos = protectedPhotos
        self.protectedFiles = protectedFiles
        self.processedItems = processedItems ?? (copiedItems + failedItems)
        self.copiedItems = copiedItems
        self.failedItems = failedItems
        self.bytesWritten = bytesWritten
        self.missedItems = missedItems
    }

    private enum CodingKeys: String, CodingKey {
        case id, planID, startedAt, finishedAt, outcome, trigger, failureReason
        case protectedPhotos, protectedFiles, processedItems, copiedItems, failedItems, bytesWritten, missedItems
    }

    /// Runs saved before `trigger`, `processedItems` and `missedItems` existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        planID = try c.decode(UUID.self, forKey: .planID)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        outcome = try c.decode(Outcome.self, forKey: .outcome)
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .manual
        failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
        protectedPhotos = try c.decode(Int.self, forKey: .protectedPhotos)
        protectedFiles = try c.decode(Int.self, forKey: .protectedFiles)
        copiedItems = try c.decode(Int.self, forKey: .copiedItems)
        failedItems = try c.decode(Int.self, forKey: .failedItems)
        bytesWritten = try c.decode(Int64.self, forKey: .bytesWritten)
        processedItems = try c.decodeIfPresent(Int.self, forKey: .processedItems) ?? (copiedItems + failedItems)
        missedItems = try c.decodeIfPresent([MissedItem].self, forKey: .missedItems) ?? []
    }

    /// Items that were already at the destination and didn't need copying.
    public var unchangedItems: Int { max(0, processedItems - copiedItems - failedItems) }

    /// The run reached the end of its work list (with or without item errors).
    public var didComplete: Bool {
        outcome == .succeeded || outcome == .completedWithErrors
    }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}
