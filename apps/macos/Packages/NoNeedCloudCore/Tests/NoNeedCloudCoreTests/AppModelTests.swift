import Foundation
import Testing
@testable import NoNeedCloudCore

@MainActor
struct AppModelTests {
    func makeModel(
        store: MemoryStore = MemoryStore(),
        engine: SimulatedBackupEngine = TestSupport.fastEngine
    ) -> AppModel {
        AppModel(store: store, engine: engine, minimumUpdateInterval: 0)
    }

    @Test func freshInstallStartsAtSetupSources() {
        let model = makeModel()
        #expect(model.screenState == .setup(.sources))
        #expect(!model.canStartBackup)
    }

    @Test func loadsSavedPlanAndRuns() {
        let store = MemoryStore()
        let plan = TestSupport.makePlan()
        store.plans = [plan]
        store.runs = [TestSupport.run(for: plan)]
        let model = makeModel(store: store)
        #expect(model.plan == plan)
        #expect(model.screenState == .protected)
    }

    @Test func editingPlanPersistsAndAdvancesSetup() {
        let store = MemoryStore()
        let model = makeModel(store: store)

        model.addFolders([TestSupport.folder("/Users/me/Documents")])
        #expect(model.plan.files.isEnabled)
        #expect(model.screenState == .setup(.destination))

        model.setDestination(TestSupport.folder("/Volumes/Backup"))
        #expect(model.screenState == .setup(.firstBackup))
        #expect(model.canStartBackup)
        #expect(store.plans == [model.plan])
    }

    @Test func addingSameFolderTwiceKeepsOne() {
        let model = makeModel()
        model.addFolders([TestSupport.folder("/a"), TestSupport.folder("/a")])
        model.addFolders([TestSupport.folder("/a")])
        #expect(model.plan.files.folders.count == 1)
    }

    @Test func removingAllFoldersReturnsToSources() {
        let model = makeModel()
        model.addFolders([TestSupport.folder("/a"), TestSupport.folder("/b")])
        model.removeFolder(TestSupport.folder("/a"))
        #expect(model.plan.files.folders.map(\.displayPath) == ["/b"])
        model.removeAllFolders()
        #expect(model.screenState == .setup(.sources))
    }

    @Test func saveErrorIsSurfaced() {
        let store = MemoryStore()
        store.failWrites = true
        let model = makeModel(store: store)
        model.updatePlan { $0.photos.isEnabled = true }
        #expect(model.saveError != nil)
        #expect(model.plan.photos.isEnabled)
    }

    @Test func completedRunIsRecordedAndProtects() async {
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = makeModel(store: store)

        model.startBackup()
        #expect(model.isRunning)
        #expect(model.screenState == .running)
        await model.waitForCurrentRun()

        #expect(!model.isRunning)
        #expect(model.progress == nil)
        #expect(model.screenState == .protected)
        let run = try? #require(model.lastRun)
        #expect(run?.outcome == .succeeded)
        #expect(run?.protectedPhotos == 12)
        #expect(run?.protectedFiles == 5)
        #expect(model.protectedPhotos == 12)
        #expect(store.runs.count == 1)
    }

    @Test func itemFailuresRecordCompletedWithErrors() async {
        var engine = TestSupport.fastEngine
        engine.failEvery = 5
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = makeModel(store: store, engine: engine)

        model.startBackup()
        await model.waitForCurrentRun()
        #expect(model.lastRun?.outcome == .completedWithErrors)
        #expect(model.lastRun?.failedItems == 3)
    }

    @Test func stoppingRecordsCancelledRun() async {
        var engine = TestSupport.fastEngine
        engine.stageDelay = .milliseconds(50)
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = makeModel(store: store, engine: engine)

        model.startBackup()
        try? await Task.sleep(for: .milliseconds(120))
        model.stopBackup()
        await model.waitForCurrentRun()

        #expect(model.lastRun?.outcome == .cancelled)
        #expect(model.screenState == .setup(.firstBackup))
    }

    @Test func cannotStartTwice() async {
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = makeModel(store: store)
        model.startBackup()
        #expect(!model.canStartBackup)
        model.startBackup()
        await model.waitForCurrentRun()
        #expect(model.runs.count == 1)
    }

    @Test func statsAcrossRuns() {
        let store = MemoryStore()
        let plan = TestSupport.makePlan()
        store.plans = [plan]
        store.runs = [
            TestSupport.run(for: plan, finishedAt: Date().addingTimeInterval(-7200), photos: 100, files: 20),
            TestSupport.run(for: plan, outcome: .cancelled, finishedAt: Date().addingTimeInterval(-3600), photos: 999, files: 999),
            TestSupport.run(for: plan, finishedAt: Date(), photos: 130, files: 25),
        ]
        let model = makeModel(store: store)
        #expect(model.protectedPhotos == 130)
        #expect(model.protectedFiles == 25)
        #expect(model.addedSinceFirstRun == 35)
        #expect(model.protectedSince == store.runs[0].finishedAt)
    }
}
