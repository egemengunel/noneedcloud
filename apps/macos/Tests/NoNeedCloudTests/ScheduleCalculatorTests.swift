import Foundation
import Testing
@testable import NoNeedCloud

struct ScheduleCalculatorTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        Self.calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private func nextRun(
        after: Date,
        schedule: Schedule,
        lastRun: Date?
    ) -> Date? {
        ScheduleCalculator.nextRun(
            after: after,
            schedule: schedule,
            lastRun: lastRun,
            calendar: Self.calendar
        )
    }

    @Test func manualNeverRuns() {
        #expect(nextRun(after: date(2026, 3, 8, 9), schedule: .manual, lastRun: nil) == nil)
        #expect(nextRun(after: date(2026, 3, 8, 9), schedule: .manual, lastRun: date(2026, 1, 1)) == nil)
    }

    @Test func hourlyAnchorsToTopOfNextHour() {
        let now = date(2026, 3, 8, 10, 30, 15)
        #expect(nextRun(after: now, schedule: .hourly, lastRun: nil) == now)
        #expect(nextRun(after: now, schedule: .hourly, lastRun: now) == date(2026, 3, 8, 11))
        #expect(nextRun(after: date(2026, 3, 8, 11), schedule: .hourly, lastRun: date(2026, 3, 8, 11))
            == date(2026, 3, 8, 12))
    }

    @Test func dailyRunsAtNineAcrossSpringForward() {
        let lastRun = date(2026, 3, 7, 9)
        let next = nextRun(
            after: date(2026, 3, 7, 10),
            schedule: .daily(hour: 9, minute: 0),
            lastRun: lastRun
        )
        #expect(next == date(2026, 3, 8, 9))
        #expect(next?.timeIntervalSince(lastRun) == TimeInterval(23 * 3600))
    }

    @Test func dailyRunsAtNineAcrossFallBack() {
        let lastRun = date(2026, 10, 31, 9)
        let next = nextRun(
            after: lastRun,
            schedule: .daily(hour: 9, minute: 0),
            lastRun: lastRun
        )
        #expect(next == date(2026, 11, 1, 9))
        #expect(next?.timeIntervalSince(lastRun) == TimeInterval(25 * 3600))
    }

    @Test func dailyAnchorIsStrictlyAfterLastRun() {
        let anchor = date(2026, 3, 8, 9)
        #expect(nextRun(after: anchor, schedule: .daily(hour: 9, minute: 0), lastRun: anchor)
            == date(2026, 3, 9, 9))
        #expect(nextRun(after: date(2026, 3, 8, 8, 59), schedule: .daily(hour: 9, minute: 0), lastRun: date(2026, 3, 7, 9))
            == date(2026, 3, 8, 9))
    }

    @Test func neverRunScheduleIsDueImmediately() {
        let now = date(2026, 3, 8, 14, 37)
        #expect(nextRun(after: now, schedule: .daily(hour: 9, minute: 0), lastRun: nil) == now)
        #expect(nextRun(after: now, schedule: .hourly, lastRun: nil) == now)
    }

    @Test func catchUpReturnsFirstMissedAnchorNotEveryMissedAnchor() {
        let lastRun = date(2026, 3, 1, 9)
        let now = date(2026, 3, 3, 14)
        #expect(nextRun(after: now, schedule: .daily(hour: 9, minute: 0), lastRun: lastRun)
            == date(2026, 3, 2, 9))
    }

    @Test func weeklyRunsOnSelectedWeekday() {
        // 2026-03-04 is a Wednesday; Calendar weekday 2 is Monday.
        let lastRun = date(2026, 3, 4, 12)
        #expect(nextRun(after: lastRun, schedule: .weekly(weekday: 2, hour: 9, minute: 0), lastRun: lastRun)
            == date(2026, 3, 9, 9))
    }

    @Test func weeklySkipsToNextWeekAfterAnchor() {
        let lastRun = date(2026, 3, 9, 9)
        #expect(nextRun(after: date(2026, 3, 9, 10), schedule: .weekly(weekday: 2, hour: 9, minute: 0), lastRun: lastRun)
            == date(2026, 3, 16, 9))
    }

    @Test func monthlyClampsDay31ToFebruary() {
        let januaryRun = date(2026, 1, 31, 9)
        #expect(nextRun(after: januaryRun, schedule: .monthly(day: 31, hour: 9, minute: 0), lastRun: januaryRun)
            == date(2026, 2, 28, 9))
    }

    @Test func monthlyResumesAtDay31AfterClamp() {
        let februaryRun = date(2026, 2, 28, 9)
        #expect(nextRun(after: date(2026, 2, 28, 10), schedule: .monthly(day: 31, hour: 9, minute: 0), lastRun: februaryRun)
            == date(2026, 3, 31, 9))
    }

    @Test func monthlyDay1AdvancesMonth() {
        let run = date(2026, 1, 1, 9)
        #expect(nextRun(after: date(2026, 1, 1, 10), schedule: .monthly(day: 1, hour: 9, minute: 0), lastRun: run)
            == date(2026, 2, 1, 9))
    }

    @Test func monthlyMidMonthAnchorsLaterSameMonth() {
        let run = date(2026, 3, 5, 12)
        #expect(nextRun(after: run, schedule: .monthly(day: 20, hour: 9, minute: 0), lastRun: run)
            == date(2026, 3, 20, 9))
    }
}
