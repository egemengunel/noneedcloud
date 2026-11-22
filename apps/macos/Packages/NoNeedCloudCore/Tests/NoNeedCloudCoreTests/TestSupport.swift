import Foundation
@testable import NoNeedCloudCore

enum TestSupport {
    static func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("noneedcloud-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func withTempStore(_ body: (JSONPlanStore, URL) throws -> Void) throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(JSONPlanStore(directory: dir), dir)
    }

    /// A reference with placeholder bookmark bytes, for tests that never touch disk.
    static func folder(_ path: String) -> FolderReference {
        FolderReference(bookmark: Data(path.utf8), displayPath: path)
    }

    static func makePlan(
        name: String = "Test Plan",
        folders: [FolderReference] = [folder("/tmp/sources")],
        photos: Bool = true,
        destination: FolderReference? = folder("/tmp/dest")
    ) -> BackupPlan {
        BackupPlan(
            name: name,
            photos: PhotoSettings(isEnabled: photos),
            files: FolderSettings(isEnabled: !folders.isEmpty, folders: folders),
            destination: destination
        )
    }

    static func run(
        for plan: BackupPlan,
        outcome: BackupRun.Outcome = .succeeded,
        finishedAt: Date = Date(),
        photos: Int = 10,
        files: Int = 5
    ) -> BackupRun {
        BackupRun(
            planID: plan.id,
            startedAt: finishedAt.addingTimeInterval(-60),
            finishedAt: finishedAt,
            outcome: outcome,
            failureReason: outcome == .failed ? "Disk full" : nil,
            protectedPhotos: photos,
            protectedFiles: files
        )
    }

    static let fastEngine = SimulatedBackupEngine(
        photoCount: 12,
        itemsPerFolder: 5,
        enumerationDelay: .zero,
        stageDelay: .zero,
        failEvery: nil
    )
}

/// In-memory store; can be told to fail writes.
final class MemoryStore: PlanStore, @unchecked Sendable {
    var plans: [BackupPlan] = []
    var runs: [BackupRun] = []
    var failWrites = false

    struct WriteFailed: Error {}

    func loadPlans() throws -> [BackupPlan] { plans }
    func savePlans(_ plans: [BackupPlan]) throws {
        if failWrites { throw WriteFailed() }
        self.plans = plans
    }
    func loadRuns() throws -> [BackupRun] { runs }
    func saveRuns(_ runs: [BackupRun]) throws {
        if failWrites { throw WriteFailed() }
        self.runs = runs
    }
}
