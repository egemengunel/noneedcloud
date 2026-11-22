import Foundation
import Testing
@testable import NoNeedCloudCore

/// A clock tests can move.
final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
struct SchedulingTests {
    private func model(store: MemoryStore, clock: TestClock, loginItem: LoginItemControl? = nil) -> AppModel {
        AppModel(store: store, engine: TestSupport.fastEngine, now: { clock.date }, loginItem: loginItem)
    }

    private func dailyPlan() -> BackupPlan {
        var plan = TestSupport.makePlan()
        plan.schedule = ScheduleSettings(frequency: .daily, timeOfDayMinutes: 2 * 60)
        return plan
    }

    private static let calendar = Calendar.current
    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func notDueBeforeTheScheduledTime() {
        let store = MemoryStore()
        store.plans = [dailyPlan()]
        let clock = TestClock(Self.date(day: 20, hour: 23))
        let model = model(store: store, clock: clock)

        clock.date = Self.date(day: 21, hour: 1, minute: 59)
        #expect(!model.runScheduledBackupIfDue())
        #expect(!model.isRunning)
    }

    @Test func startsOnceWhenDueAndRecordsAScheduledRun() async {
        let store = MemoryStore()
        store.plans = [dailyPlan()]
        let clock = TestClock(Self.date(day: 20, hour: 23))
        let model = model(store: store, clock: clock)

        clock.date = Self.date(day: 21, hour: 2, minute: 1)
        #expect(model.runScheduledBackupIfDue())
        #expect(!model.runScheduledBackupIfDue())
        await model.waitForCurrentRun()

        #expect(model.lastRun?.trigger == .scheduled)
        // Anchored to the run just made: the next one is tomorrow.
        #expect(!model.runScheduledBackupIfDue())
        #expect(model.scheduledRunDue == Self.date(day: 22, hour: 2))
    }

    @Test func aRunSleptThroughIsCaughtUpOnce() async {
        let store = MemoryStore()
        let plan = dailyPlan()
        store.plans = [plan]
        store.runs = [TestSupport.run(for: plan, finishedAt: Self.date(day: 18, hour: 2, minute: 5))]
        let clock = TestClock(Self.date(day: 21, hour: 9))
        let model = model(store: store, clock: clock)

        #expect(model.runScheduledBackupIfDue())
        await model.waitForCurrentRun()
        #expect(!model.runScheduledBackupIfDue())
        #expect(model.planRuns.count == 2)
    }

    @Test func manualPlansNeverRunOnTheirOwn() {
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let clock = TestClock(Self.date(day: 20, hour: 23))
        let model = model(store: store, clock: clock)
        clock.date = Self.date(day: 25, hour: 12)
        #expect(model.scheduledRunDue == nil)
        #expect(!model.runScheduledBackupIfDue())
    }

    @Test func startAtLoginTogglesTheLoginItem() {
        final class Box: @unchecked Sendable { var enabled = false }
        let box = Box()
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = model(
            store: store,
            clock: TestClock(Date()),
            loginItem: LoginItemControl(isEnabled: { box.enabled }, setEnabled: { box.enabled = $0 })
        )

        model.updatePlan { $0.schedule.startAtLogin = true }
        #expect(box.enabled)
        #expect(model.plan.schedule.startAtLogin)

        model.updatePlan { $0.schedule.startAtLogin = false }
        #expect(!box.enabled)
    }

    @Test func loginItemRemovedInSystemSettingsIsReflected() {
        let store = MemoryStore()
        var plan = TestSupport.makePlan()
        plan.schedule.startAtLogin = true
        store.plans = [plan]
        let model = model(
            store: store,
            clock: TestClock(Date()),
            loginItem: LoginItemControl(isEnabled: { false }, setEnabled: { _ in })
        )
        #expect(!model.plan.schedule.startAtLogin)
    }

    @Test func failingLoginItemKeepsTheRealState() {
        struct Denied: Error {}
        let store = MemoryStore()
        store.plans = [TestSupport.makePlan()]
        let model = model(
            store: store,
            clock: TestClock(Date()),
            loginItem: LoginItemControl(isEnabled: { false }, setEnabled: { _ in throw Denied() })
        )
        model.updatePlan { $0.schedule.startAtLogin = true }
        #expect(!model.plan.schedule.startAtLogin)
        #expect(model.saveError != nil)
    }
}
