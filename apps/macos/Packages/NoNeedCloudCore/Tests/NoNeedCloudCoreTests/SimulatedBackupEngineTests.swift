import Foundation
import Testing
@testable import NoNeedCloudCore

struct SimulatedBackupEngineTests {
    func collect(_ engine: SimulatedBackupEngine, _ plan: BackupPlan) async throws -> [BackupProgress] {
        var updates: [BackupProgress] = []
        for try await update in engine.run(plan) { updates.append(update) }
        return updates
    }

    @Test func walksEveryItemAndFinishes() async throws {
        let plan = TestSupport.makePlan(folders: [TestSupport.folder("/tmp/a"), TestSupport.folder("/tmp/b")])
        let updates = try await collect(TestSupport.fastEngine, plan)
        let last = try #require(updates.last)

        #expect(updates.first?.phase == .enumerating)
        #expect(updates.first?.totalItems == nil)
        #expect(last.phase == .finished)
        #expect(last.totalItems == 12 + 2 * 5)
        #expect(last.processedItems == 22)
        #expect(last.processedPhotos == 12)
        #expect(last.processedFiles == 10)
        #expect(last.fractionCompleted == 1)
    }

    @Test func filesGoThroughReleaseStagePhotosDoNot() async throws {
        let updates = try await collect(TestSupport.fastEngine, TestSupport.makePlan())
        let photoStages = Set(updates.compactMap { $0.currentItem }.filter { $0.kind == .photo }.map(\.stage))
        let fileStages = Set(updates.compactMap { $0.currentItem }.filter { $0.kind == .file }.map(\.stage))
        #expect(photoStages == [.check, .fetch, .write])
        #expect(fileStages == [.check, .fetch, .write, .release])
    }

    @Test func disabledSourcesProduceNoItems() async throws {
        var plan = TestSupport.makePlan()
        plan.photos.isEnabled = false
        plan.files.isEnabled = false
        let last = try #require(try await collect(TestSupport.fastEngine, plan).last)
        #expect(last.totalItems == 0)
        #expect(last.phase == .finished)
    }

    @Test func failuresAreCountedNotCopied() async throws {
        var engine = TestSupport.fastEngine
        engine.failEvery = 4
        let last = try #require(try await collect(engine, TestSupport.makePlan(folders: [])).last)
        #expect(last.failedItems == 3)
        #expect(last.copiedItems == 9)
        #expect(last.processedItems == 12)
    }
}
