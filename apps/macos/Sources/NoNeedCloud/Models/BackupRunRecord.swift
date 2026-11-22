import Foundation

struct BackupRunRecord: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var planId: UUID
    var start: Date
    var end: Date
    var outcome: CopyRunResult.Outcome
    var itemsCopied: Int
    var itemsSkipped: Int
    var itemsFailed: Int
    var bytesCopied: Int64
    var errors: [BackupFileError]
}
