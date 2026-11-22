import Foundation
import Testing
@testable import NoNeedCloud

struct RunHistoryStoreTests {
    @Test func loadReturnsEmptyWhenNoFileExists() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONRunHistoryStore(directory: dir)
        #expect(try store.loadRecords() == [])
    }

    @Test func appendPersistsRecordsAcrossInstances() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONRunHistoryStore(directory: dir)
        let first = Self.makeRecord(planId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let second = Self.makeRecord(
            planId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            outcome: .failed,
            errors: [BackupFileError(path: "locked.txt", reason: "Permission denied")]
        )

        try store.append(first)
        try store.append(second)

        let reloaded = JSONRunHistoryStore(directory: dir)
        #expect(try reloaded.loadRecords() == [first, second])
    }

    @Test func appendKeepsAllRuns() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONRunHistoryStore(directory: dir)

        for _ in 0..<5 {
            try store.append(Self.makeRecord())
        }

        #expect(try store.loadRecords().count == 5)
    }

    @Test func appendIsAtomicAndLeavesValidFileOnDisk() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONRunHistoryStore(directory: dir)
        try store.append(Self.makeRecord())

        let contents = try String(contentsOf: dir.appendingPathComponent("history.json"), encoding: .utf8)
        let json = try JSONSerialization.jsonObject(with: Data(contents.utf8))
        #expect(!contents.isEmpty)
        #expect((json as? [[String: Any]])?.count == 1)
    }

    private static func makeRecord(
        planId: UUID = UUID(),
        outcome: CopyRunResult.Outcome = .completed,
        errors: [BackupFileError] = []
    ) -> BackupRunRecord {
        BackupRunRecord(
            planId: planId,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 105),
            outcome: outcome,
            itemsCopied: 3,
            itemsSkipped: 1,
            itemsFailed: errors.count,
            bytesCopied: 42,
            errors: errors
        )
    }
}
