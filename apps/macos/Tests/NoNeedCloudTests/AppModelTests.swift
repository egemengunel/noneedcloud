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

    @Test @MainActor func backupAppendsHistoryRecordAndPersistsAcrossRelaunch() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("two".utf8).write(to: source.appendingPathComponent("b.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let runState = root.appendingPathComponent("RunState", isDirectory: true)
        let model = AppModel(store: store, runStateDirectory: runState)
        let plan = TestSupport.makePlan(name: "Real", sources: [source], destination: destination)

        let results = await model.backup(plan)

        #expect(model.history.count == 1)
        let record = model.history[0]
        #expect(record.planId == plan.id)
        #expect(record.outcome == .completed)
        #expect(record.itemsCopied == 2)
        #expect(record.itemsSkipped == 0)
        #expect(record.itemsFailed == 0)
        #expect(record.bytesCopied == 6)
        #expect(record.end >= record.start)
        #expect(record.errors.isEmpty)
        #expect(results[0].outcome == .completed)

        let relaunched = AppModel(store: store, runStateDirectory: runState)
        #expect(relaunched.history == model.history)
    }

    @Test @MainActor func multiSourceRunProducesSingleAggregatedRecord() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: first.appendingPathComponent("a.txt"))
        try Data("two".utf8).write(to: second.appendingPathComponent("b.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Two Sources", sources: [first, second], destination: destination)

        _ = await model.backup(plan)

        #expect(model.history.count == 1)
        let record = model.history[0]
        #expect(record.itemsCopied == 2)
        #expect(record.outcome == .completed)
    }

    @Test @MainActor func unreadableFilesAppearInMissedItemsWithReasons() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("readable".utf8).write(to: source.appendingPathComponent("ok.txt"))
        let lockedPath = source.appendingPathComponent("locked.txt")
        try Data("secret".utf8).write(to: lockedPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath.path) }
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Locked", sources: [source], destination: destination)

        _ = await model.backup(plan)

        #expect(model.history.count == 1)
        let record = model.history[0]
        #expect(record.itemsFailed == 1)
        #expect(record.itemsCopied == 1)
        #expect(record.errors.count == 1)
        #expect(record.errors[0].path == "locked.txt")
        #expect(!record.errors[0].reason.isEmpty)

        let missed = model.missedItems(for: plan.id)
        #expect(missed.count == 1)
        #expect(missed[0].path == "locked.txt")
        #expect(!missed[0].reason.isEmpty)
    }

    @Test @MainActor func successfulSecondRunClearsMissedItemsAndAppendsRecord() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let lockedPath = source.appendingPathComponent("locked.txt")
        try Data("secret".utf8).write(to: lockedPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath.path) }
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Retry", sources: [source], destination: destination)

        _ = await model.backup(plan)
        #expect(model.missedItems(for: plan.id).count == 1)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath.path)
        _ = await model.backup(plan)

        #expect(model.history.count == 2)
        #expect(model.history[0].itemsFailed == 1)
        #expect(model.history[1].outcome == .completed)
        #expect(model.history[1].itemsFailed == 0)
        #expect(model.history[1].itemsCopied == 1)
        #expect(model.history[1].errors.isEmpty)
        #expect(model.missedItems(for: plan.id).isEmpty)
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

    @Test @MainActor func failedSourceDoesNotStopRemainingSources() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let good = root.appendingPathComponent("Good", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: good.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Mixed", sources: [missing, good], destination: destination)

        let results = await model.backup(plan)

        #expect(results.count == 2)
        #expect(results[0].outcome == .failed)
        #expect(results[1].outcome == .completed)
        #expect(results[1].itemsCopied == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Good/a.txt")) == Data("kept".utf8))
        #expect(model.history.count == 1)
        #expect(model.history[0].outcome == .failed)
        #expect(model.history[0].errors.contains { $0.path == missing.path })
        #expect(model.lastBackupDate == nil)
    }

    @Test @MainActor func addUpdateDeletePlansPersistAcrossRelaunch() throws {
        try TestSupport.withTempStore { store, dir in
            let model = AppModel(store: store)
            let first = TestSupport.makePlan(name: "First")
            let second = TestSupport.makePlan(name: "Second")

            model.addPlan(first)
            model.addPlan(second)
            #expect(model.plans.map(\.name) == ["First", "Second"])

            var renamed = first
            renamed.name = "Renamed"
            renamed.schedule = .daily(hour: 9, minute: 0)
            model.updatePlan(renamed)
            #expect(model.plans.map(\.name) == ["Renamed", "Second"])
            #expect(model.plans[0].schedule == .daily(hour: 9, minute: 0))

            let renamedRelaunch = AppModel(store: JSONPlanStore(directory: dir))
            #expect(renamedRelaunch.plans.map(\.name) == ["Renamed", "Second"])
            #expect(renamedRelaunch.plans[0].schedule == .daily(hour: 9, minute: 0))

            model.deletePlan(first.id)
            #expect(model.plans.map(\.name) == ["Second"])

            let relaunched = AppModel(store: JSONPlanStore(directory: dir))
            #expect(relaunched.plans.map(\.name) == ["Second"])
        }
    }

    @Test @MainActor func updatingUnknownPlanIsIgnored() throws {
        try TestSupport.withTempStore { store, _ in
            let model = AppModel(store: store)
            let plan = TestSupport.makePlan(name: "Real")
            model.addPlan(plan)

            var stranger = TestSupport.makePlan(name: "Stranger")
            stranger.id = UUID()
            model.updatePlan(stranger)

            #expect(model.plans.map(\.name) == ["Real"])
        }
    }

    @Test @MainActor func deletePlanKeepsHistoryAndMissedItems() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let lockedPath = source.appendingPathComponent("locked.txt")
        try Data("secret".utf8).write(to: lockedPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath.path) }
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Doomed", sources: [source], destination: destination)

        _ = await model.backup(plan)
        #expect(model.missedItems(for: plan.id).count == 1)

        model.deletePlan(plan.id)
        #expect(model.plans.isEmpty)
        #expect(model.history.count == 1)
        #expect(model.missedItems(for: plan.id).count == 1)

        let relaunched = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        #expect(relaunched.history.count == 1)
        #expect(relaunched.missedItems(for: plan.id).count == 1)
    }

    @Test @MainActor func startBackupMarksPlanRunningUntilFinished() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Real", sources: [source], destination: destination)

        model.startBackup(plan)
        #expect(model.isPlanRunning(plan.id))

        await waitForPlanIdle(model, plan.id)
        #expect(!model.isPlanRunning(plan.id))
        #expect(model.history.count == 1)
    }

    @Test @MainActor func concurrentBackupsSerializeThroughGlobalGuard() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Real", sources: [source], destination: destination)

        async let first = model.backup(plan)
        async let second = model.backup(plan)
        let results = await [first, second]

        #expect(results.filter(\.isEmpty).count == 1)
        #expect(model.history.count == 1)
    }

    @Test @MainActor func sameSourceDifferentDestinationsBackUpIndependently() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destinationA = root.appendingPathComponent("DestA", isDirectory: true)
        let destinationB = root.appendingPathComponent("DestB", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let planA = TestSupport.makePlan(name: "A", sources: [source], destination: destinationA)
        let planB = TestSupport.makePlan(name: "B", sources: [source], destination: destinationB)

        let resultsA = await model.backup(planA)
        let resultsB = await model.backup(planB)

        #expect(resultsA[0].itemsCopied == 1)
        #expect(resultsB[0].itemsCopied == 1)
        #expect(try Data(contentsOf: destinationA.appendingPathComponent("Source/a.txt")) == Data("one".utf8))
        #expect(try Data(contentsOf: destinationB.appendingPathComponent("Source/a.txt")) == Data("one".utf8))
        #expect(model.history.map(\.planId) == [planA.id, planB.id])
    }

    @Test @MainActor func lastRunDateTracksMostRecentRecordEnd() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: source.appendingPathComponent("a.txt"))
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true))
        let plan = TestSupport.makePlan(name: "Real", sources: [source], destination: destination)

        #expect(model.lastRunDate(for: plan.id) == nil)

        _ = await model.backup(plan)
        #expect(model.lastRunDate(for: plan.id) == model.history[0].end)

        _ = await model.backup(plan)
        #expect(model.lastRunDate(for: plan.id) == model.history[1].end)
        #expect(model.lastRunDate(for: UUID()) == nil)
    }
}

@MainActor
private func waitForPlanIdle(_ model: AppModel, _ planId: UUID) async {
    for _ in 0..<2000 {
        if !model.isPlanRunning(planId) { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    Issue.record("Backup did not finish in time")
}
