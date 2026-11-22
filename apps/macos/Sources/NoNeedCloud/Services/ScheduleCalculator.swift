import Foundation

/// Pure schedule math. `nextRun` returns the next instant the schedule is due:
///
/// - `.manual` never runs (nil).
/// - A plan that has never run is due at `now` itself, so the first tick after
///   it gains a schedule starts it right away.
/// - Otherwise the anchor is the next scheduled instant strictly after
///   `lastRun`. That anchor can be in the past relative to `now`: that is the
///   catch-up signal for runs the Mac slept through. The caller runs once and
///   re-anchors from the completed run's time, so a long sleep still starts
///   exactly one run.
enum ScheduleCalculator {
    static func nextRun(
        after now: Date,
        schedule: Schedule,
        lastRun: Date?,
        calendar: Calendar
    ) -> Date? {
        guard schedule != .manual else { return nil }
        guard let lastRun else { return now }
        switch schedule {
        case .manual:
            return nil
        case .hourly:
            var components = DateComponents()
            components.minute = 0
            components.second = 0
            return calendar.nextDate(after: lastRun, matching: components, matchingPolicy: .nextTime)
        case .daily(let hour, let minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return calendar.nextDate(after: lastRun, matching: components, matchingPolicy: .nextTime)
        case .weekly(let weekday, let hour, let minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            return calendar.nextDate(after: lastRun, matching: components, matchingPolicy: .nextTime)
        case .monthly(let day, let hour, let minute):
            return nextMonthlyAnchor(after: lastRun, day: day, hour: hour, minute: minute, calendar: calendar)
        }
    }

    /// Day-of-month anchors can't use `nextDate` because it would skip months
    /// that lack the day (day 31 never matches February). Instead walk month
    /// by month and clamp the day to the month's last day.
    private static func nextMonthlyAnchor(
        after reference: Date,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        var probe = reference
        for _ in 0..<100 {
            guard let monthStart = calendar.dateInterval(of: .month, for: probe)?.start else { return nil }
            var components = calendar.dateComponents([.year, .month], from: monthStart)
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
            guard let year = components.year, let month = components.month, let daysInMonth else { return nil }
            components.day = min(day, daysInMonth)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let anchor = calendar.date(from: components) else { return nil }
            if anchor > reference { return anchor }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
            probe = nextMonth
        }
        return nil
    }
}
