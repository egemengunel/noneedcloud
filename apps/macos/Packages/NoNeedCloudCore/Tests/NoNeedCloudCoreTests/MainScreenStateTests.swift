import Foundation
import Testing
@testable import NoNeedCloudCore

struct MainScreenStateTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func derive(
        _ plan: BackupPlan,
        runs: [BackupRun] = [],
        running: Bool = false,
        health: HealthSnapshot = HealthSnapshot()
    ) -> MainScreenState {
        MainScreenState.derive(plan: plan, runs: runs, isRunning: running, health: health, now: now)
    }

    @Test func freshPlanStartsAtSources() {
        #expect(derive(BackupPlan()) == .setup(.sources))
    }

    @Test func enabledFolderToggleWithoutFoldersIsStillSources() {
        var plan = BackupPlan()
        plan.files.isEnabled = true
        #expect(derive(plan) == .setup(.sources))
    }

    @Test func sourcesWithoutDestinationAsksForDestination() {
        #expect(derive(TestSupport.makePlan(destination: nil)) == .setup(.destination))
    }

    @Test func readyPlanWithoutRunsIsFirstBackup() {
        #expect(derive(TestSupport.makePlan()) == .setup(.firstBackup))
    }

    @Test func cancelledFirstRunStaysOnFirstBackup() {
        let plan = TestSupport.makePlan()
        #expect(derive(plan, runs: [TestSupport.run(for: plan, outcome: .cancelled)]) == .setup(.firstBackup))
    }

    @Test func runningWinsOverEverything() {
        #expect(derive(BackupPlan(), running: true) == .running)
    }

    @Test func recentSuccessIsProtected() {
        let plan = TestSupport.makePlan()
        let run = TestSupport.run(for: plan, finishedAt: now.addingTimeInterval(-3600))
        #expect(derive(plan, runs: [run]) == .protected)
    }

    @Test func completedWithErrorsStillCountsAsProtected() {
        let plan = TestSupport.makePlan()
        let run = TestSupport.run(for: plan, outcome: .completedWithErrors, finishedAt: now)
        #expect(derive(plan, runs: [run]) == .protected)
    }

    @Test func lastRunFailureNeedsAttention() {
        let plan = TestSupport.makePlan()
        let runs = [
            TestSupport.run(for: plan, finishedAt: now.addingTimeInterval(-7200)),
            TestSupport.run(for: plan, outcome: .failed, finishedAt: now.addingTimeInterval(-60)),
        ]
        #expect(derive(plan, runs: runs) == .needsAttention(.lastRunFailed(reason: "Disk full")))
    }

    @Test func oldSuccessIsStale() {
        let plan = TestSupport.makePlan()
        let run = TestSupport.run(for: plan, finishedAt: now.addingTimeInterval(-8 * 86_400))
        #expect(derive(plan, runs: [run]) == .needsAttention(.backupStale(days: 8)))
    }

    @Test func missingDestinationNeedsAttention() {
        let plan = TestSupport.makePlan(destination: TestSupport.folder("/Volumes/Backup Drive"))
        let run = TestSupport.run(for: plan, finishedAt: now)
        let state = derive(plan, runs: [run], health: HealthSnapshot(destinationAvailable: false))
        #expect(state == .needsAttention(.destinationUnavailable(name: "Backup Drive")))
    }

    @Test func deniedPhotosOnlyMattersWhenPhotosEnabled() {
        let withPhotos = TestSupport.makePlan(photos: true)
        let withoutPhotos = TestSupport.makePlan(photos: false)
        let denied = HealthSnapshot(photosAccessGranted: false)
        #expect(derive(withPhotos, runs: [TestSupport.run(for: withPhotos, finishedAt: now)], health: denied)
            == .needsAttention(.photosAccessDenied))
        #expect(derive(withoutPhotos, runs: [TestSupport.run(for: withoutPhotos, finishedAt: now)], health: denied)
            == .protected)
    }

    @Test func runsOfOtherPlansAreIgnored() {
        let plan = TestSupport.makePlan()
        let other = TestSupport.makePlan()
        #expect(derive(plan, runs: [TestSupport.run(for: other, finishedAt: now)]) == .setup(.firstBackup))
    }
}
