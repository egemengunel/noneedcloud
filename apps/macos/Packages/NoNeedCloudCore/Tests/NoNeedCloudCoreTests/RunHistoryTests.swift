import Foundation
import Testing
@testable import NoNeedCloudCore

struct RunHistoryTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func run(_ outcome: BackupRun.Outcome, _ date: Date, missed: [MissedItem] = []) -> BackupRun {
        BackupRun(planID: UUID(), startedAt: date, finishedAt: date.addingTimeInterval(60), outcome: outcome,
                  copiedItems: 10, failedItems: missed.count, missedItems: missed)
    }

    @Test func groupsByDayNewestFirst() {
        let runs = [
            run(.succeeded, at(20, 23, 2)),
            run(.succeeded, at(22, 9, 18)),
            run(.cancelled, at(21, 16, 44)),
            run(.completedWithErrors, at(22, 10, 16)),
            run(.succeeded, at(21, 22, 51)),
        ]
        let days = RunHistory.days(from: runs, calendar: calendar)
        #expect(days.count == 3)
        #expect(days[0].runs.map(\.startedAt) == [at(22, 10, 16), at(22, 9, 18)])
        #expect(days[1].runs.map(\.startedAt) == [at(21, 22, 51), at(21, 16, 44)])
        #expect(days[2].runs.count == 1)
    }

    @Test func filterKeepsMatchingOutcomes() {
        let runs = [run(.succeeded, at(22, 9, 0)), run(.cancelled, at(22, 10, 0)), run(.completedWithErrors, at(22, 11, 0))]
        #expect(RunHistory.days(from: runs, filter: .stopped, calendar: calendar).flatMap(\.runs).map(\.outcome) == [.cancelled])
        #expect(RunHistory.days(from: runs, filter: .withWarnings, calendar: calendar).flatMap(\.runs).count == 1)
        #expect(RunHistory.days(from: runs, filter: .failed, calendar: calendar).isEmpty)
    }

    @Test func searchFindsMissedFileNames() {
        let missed = [MissedItem(name: "IMG_2841.HEIC", location: "iCloud Photos", reason: "The iCloud download stopped partway.")]
        let runs = [run(.completedWithErrors, at(22, 10, 16), missed: missed), run(.succeeded, at(22, 9, 18))]
        #expect(RunHistory.days(from: runs, search: "img_2841", calendar: calendar).flatMap(\.runs).count == 1)
        #expect(RunHistory.days(from: runs, search: "download", calendar: calendar).flatMap(\.runs).count == 1)
        #expect(RunHistory.days(from: runs, search: "   ", calendar: calendar).flatMap(\.runs).count == 2)
    }
}

struct BackupRunCompatibilityTests {
    @Test func oldRunsWithoutNewFieldsStillDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","planID":"\(UUID().uuidString)","startedAt":0,"finishedAt":60,
          "outcome":"succeeded","protectedPhotos":1,"protectedFiles":2,"copiedItems":5,"failedItems":1,"bytesWritten":10}]
        """
        let runs = try JSONDecoder().decode([BackupRun].self, from: Data(json.utf8))
        #expect(runs[0].trigger == .manual)
        #expect(runs[0].processedItems == 6)
        #expect(runs[0].missedItems.isEmpty)
        #expect(runs[0].unchangedItems == 0)
    }

    @Test func unchangedIsProcessedMinusCopiedAndFailed() {
        let run = BackupRun(planID: UUID(), startedAt: .now, finishedAt: .now, outcome: .completedWithErrors,
                            processedItems: 27_462, copiedItems: 2_498, failedItems: 3)
        #expect(run.unchangedItems == 24_961)
    }
}

@MainActor
struct MissedItemRecordingTests {
    @Test func failedItemsAreRecordedWithReasons() async {
        var engine = TestSupport.fastEngine
        engine.failEvery = 4
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan(folders: [])]
        let model = AppModel(store: store, engine: engine, minimumUpdateInterval: 0)
        model.startBackup()
        await model.waitForCurrentRun()

        let run = model.lastRun
        #expect(run?.missedItems.count == 3)
        #expect(run?.missedItems.first?.location == "iCloud Photos")
        #expect(run?.missedItems.allSatisfy { !$0.reason.isEmpty } == true)
        #expect(run?.processedItems == 12)
        #expect(run?.trigger == .manual)
    }
}
