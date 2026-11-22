import Foundation
import Testing
@testable import NoNeedCloudCore

struct ScheduleTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func offHasNoNextRun() {
        #expect(ScheduleSettings(frequency: .off).nextRun(after: .now, calendar: calendar) == nil)
    }

    @Test func dailyLaterTodayOrTomorrow() {
        let schedule = ScheduleSettings(frequency: .daily, timeOfDayMinutes: 23 * 60)
        #expect(schedule.nextRun(after: date(2026, 11, 22, 9, 18), calendar: calendar) == date(2026, 11, 22, 23, 0))
        #expect(schedule.nextRun(after: date(2026, 11, 22, 23, 30), calendar: calendar) == date(2026, 11, 23, 23, 0))
    }

    @Test func hourlyOnTheHour() {
        let schedule = ScheduleSettings(frequency: .hourly)
        #expect(schedule.nextRun(after: date(2026, 11, 22, 9, 18), calendar: calendar) == date(2026, 11, 22, 10, 0))
    }

    @Test func weeklyOnChosenWeekday() {
        // 22 Nov 2026 is a Sunday; weekday 2 = Monday.
        let schedule = ScheduleSettings(frequency: .weekly, timeOfDayMinutes: 2 * 60, weekday: 2)
        #expect(schedule.nextRun(after: date(2026, 11, 22, 12, 0), calendar: calendar) == date(2026, 11, 23, 2, 0))
    }

    @Test func monthlyOnChosenDay() {
        let schedule = ScheduleSettings(frequency: .monthly, timeOfDayMinutes: 60, dayOfMonth: 1)
        #expect(schedule.nextRun(after: date(2026, 11, 22, 12, 0), calendar: calendar) == date(2026, 12, 1, 1, 0))
    }
}

struct SetupNavigationTests {
    @Test func withoutRequestShowsReachedStep() {
        #expect(MainScreenState.visibleStep(requested: nil, reached: .destination) == .destination)
    }

    @Test func backGoesToEarlierStep() {
        #expect(MainScreenState.visibleStep(requested: .sources, reached: .firstBackup) == .sources)
    }

    @Test func cannotSkipAhead() {
        #expect(MainScreenState.visibleStep(requested: .firstBackup, reached: .sources) == .sources)
    }
}

struct DestinationDetailsTests {
    @Test func tempFolderIsAWritableLocalDisk() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let details = try #require(DestinationDetails.inspect(dir))
        #expect(details.kind != .network)
        #expect(details.isWritable)
        #expect((details.freeBytes ?? 0) > 0)
        #expect(!details.volumeName.isEmpty)
    }

    @Test func healthInspectsReachableDestination() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DestinationHealth.inspect(try FolderReference(url: dir)) != nil)
    }

    @Test func healthIsNilForMissingFolder() throws {
        let parent = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("Gone", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reference = try FolderReference(url: folder)
        try FileManager.default.removeItem(at: folder)
        #expect(DestinationHealth.inspect(reference) == nil)
    }
}

@MainActor
struct HealthPersistenceTests {
    @Test func refreshHealthRemembersDestinationDetails() async {
        let details = DestinationDetails(volumeName: "Home Archive", kind: .network, networkProtocol: "SMB", isWritable: true)
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = AppModel(
            store: store,
            engine: TestSupport.fastEngine,
            healthCheck: { _ in HealthSnapshot(destination: details) }
        )
        await model.refreshHealth()
        #expect(model.plan.destinationDetails == details)
        #expect(store.plans.first?.destinationDetails == details)
    }

    @Test func changingDestinationForgetsOldDetails() {
        var plan = TestSupport.makePlan()
        plan.destinationDetails = DestinationDetails(volumeName: "Old", kind: .externalDisk, isWritable: true)
        let store = MemoryStore()
        store.plans = [plan]
        let model = AppModel(store: store, engine: TestSupport.fastEngine)
        model.setDestination(TestSupport.folder("/Volumes/New"))
        #expect(model.plan.destinationDetails == nil)
    }
}
