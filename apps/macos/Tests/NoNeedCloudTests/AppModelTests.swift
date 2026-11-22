import Foundation
import Testing
@testable import NoNeedCloud

struct AppModelTests {
    @Test @MainActor func freshInstallNeedsSetup() throws {
        try TestSupport.withTempStore { store, _ in
            let model = AppModel(store: store)
            #expect(model.isSetupNeeded)
            #expect(model.plans.isEmpty)
        }
    }

    @Test @MainActor func completedSetupFlagSkipsSetupEvenWithoutPlans() throws {
        try TestSupport.withTempStore { store, _ in
            try store.setSetupCompleted(true)
            let model = AppModel(store: store)
            #expect(!model.isSetupNeeded)
        }
    }

    @Test @MainActor func existingPlansSkipSetup() throws {
        try TestSupport.withTempStore { store, _ in
            try store.savePlans([TestSupport.makePlan()])
            let model = AppModel(store: store)
            #expect(!model.isSetupNeeded)
        }
    }

    @Test @MainActor func finishSetupAddsPlanAndPersistsEverything() throws {
        try TestSupport.withTempStore { store, dir in
            let model = AppModel(store: store)
            let plan = TestSupport.makePlan(name: "My First Backup")

            model.finishSetup(plan)

            #expect(model.plans == [plan])
            #expect(model.isSetupCompleted)
            #expect(!model.isSetupNeeded)

            let relaunched = AppModel(store: JSONPlanStore(directory: dir))
            #expect(relaunched.plans == [plan])
            #expect(relaunched.isSetupCompleted)
            #expect(!relaunched.isSetupNeeded)
        }
    }

    @Test @MainActor func backupCopiesPlanSourcesAndUpdatesGlanceState() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("two".utf8).write(to: source.appendingPathComponent("nested/b.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(
            name: "Real",
            sources: [source],
            destination: destination
        )

        let results = await model.backup(plan)

        #expect(results.count == 1)
        #expect(results[0].outcome == .completed)
        #expect(results[0].itemsCopied == 2)
        #expect(model.lastBackupDate != nil)
        #expect(model.itemsProtected == 2)
        #expect(model.activeEngine == nil)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Source/a.txt")) == Data("one".utf8))
        #expect(try Data(contentsOf: destination.appendingPathComponent("Source/nested/b.txt")) == Data("two".utf8))
    }

    @Test @MainActor func secondBackupSkipsUnchangedItems() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Real", sources: [source], destination: destination)

        _ = await model.backup(plan)
        let second = await model.backup(plan)

        #expect(second[0].itemsCopied == 0)
        #expect(second[0].itemsSkipped == 1)
        #expect(model.itemsProtected == 1)
    }
}
