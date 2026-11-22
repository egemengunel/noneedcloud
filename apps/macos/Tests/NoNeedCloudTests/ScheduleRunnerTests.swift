import Foundation
import Testing
@testable import NoNeedCloud

@MainActor
private final class SchedulerSpy: PlanScheduling {
    var plans: [BackupPlan] = []
    var runningIds: Set<UUID> = []
    var lastRuns: [UUID: Date] = [:]
    private(set) var started: [UUID] = []

    func isPlanRunning(_ planId: UUID) -> Bool {
        runningIds.contains(planId)
    }

    func lastRunDate(for planId: UUID) -> Date? {
        lastRuns[planId]
    }

    func startBackup(_ plan: BackupPlan) {
        started.append(plan.id)
    }
}

struct ScheduleRunnerTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @MainActor
    private func makeRunner(spy: SchedulerSpy, now: Date) -> ScheduleRunner {
        ScheduleRunner(scheduler: spy, calendar: Self.calendar, clock: { now })
    }

    @Test @MainActor func duePlanStartsOnTick() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .daily(hour: 9, minute: 0))
        spy.plans = [plan]
        spy.lastRuns[plan.id] = date(2026, 3, 7, 9)
        makeRunner(spy: spy, now: date(2026, 3, 8, 9, 30)).tick()
        #expect(spy.started == [plan.id])
    }

    @Test @MainActor func futureAnchorDoesNotStart() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .daily(hour: 9, minute: 0))
        spy.plans = [plan]
        spy.lastRuns[plan.id] = date(2026, 3, 8, 9)
        makeRunner(spy: spy, now: date(2026, 3, 8, 10)).tick()
        #expect(spy.started.isEmpty)
    }

    @Test @MainActor func runningPlanIsSkipped() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .hourly)
        spy.plans = [plan]
        spy.lastRuns[plan.id] = date(2026, 3, 8, 10)
        spy.runningIds = [plan.id]
        makeRunner(spy: spy, now: date(2026, 3, 8, 11)).tick()
        #expect(spy.started.isEmpty)
    }

    @Test @MainActor func manualPlanNeverStarts() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .manual)
        spy.plans = [plan]
        makeRunner(spy: spy, now: date(2026, 3, 8, 11)).tick()
        #expect(spy.started.isEmpty)
    }

    @Test @MainActor func neverRunScheduledPlanStartsOnFirstTick() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .daily(hour: 9, minute: 0))
        spy.plans = [plan]
        makeRunner(spy: spy, now: date(2026, 3, 8, 14, 37)).tick()
        #expect(spy.started == [plan.id])
    }

    @Test @MainActor func catchUpStartsMissedPlanExactlyOnce() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .daily(hour: 9, minute: 0))
        spy.plans = [plan]
        spy.lastRuns[plan.id] = date(2026, 3, 1, 9)
        let runner = makeRunner(spy: spy, now: date(2026, 3, 3, 14))

        runner.tick()
        #expect(spy.started == [plan.id])

        spy.lastRuns[plan.id] = date(2026, 3, 3, 14, 5)
        runner.tick()
        #expect(spy.started.count == 1)
    }

    @Test @MainActor func hourlyFiresAtExactAnchor() {
        let spy = SchedulerSpy()
        let plan = TestSupport.makePlan(schedule: .hourly)
        spy.plans = [plan]
        spy.lastRuns[plan.id] = date(2026, 3, 8, 10)
        makeRunner(spy: spy, now: date(2026, 3, 8, 11)).tick()
        #expect(spy.started == [plan.id])
    }

    @Test @MainActor func multiplePlansStartIndependently() {
        let spy = SchedulerSpy()
        let hourly = TestSupport.makePlan(name: "Hourly", schedule: .hourly)
        let daily = TestSupport.makePlan(name: "Daily", schedule: .daily(hour: 9, minute: 0))
        let manual = TestSupport.makePlan(name: "Manual", schedule: .manual)
        spy.plans = [hourly, daily, manual]
        spy.lastRuns[hourly.id] = date(2026, 3, 8, 10)
        spy.lastRuns[daily.id] = date(2026, 3, 7, 9)
        makeRunner(spy: spy, now: date(2026, 3, 8, 11, 30)).tick()
        #expect(Set(spy.started) == [hourly.id, daily.id])
    }
}
