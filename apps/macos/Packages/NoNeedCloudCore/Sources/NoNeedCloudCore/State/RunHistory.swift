import Foundation

/// Filtering and day grouping for the Backup History window.
public enum RunHistory {
    public enum Filter: String, CaseIterable, Sendable {
        case all, succeeded, withWarnings, stopped, failed

        public func matches(_ run: BackupRun) -> Bool {
            switch self {
            case .all: true
            case .succeeded: run.outcome == .succeeded
            case .withWarnings: run.outcome == .completedWithErrors
            case .stopped: run.outcome == .cancelled
            case .failed: run.outcome == .failed
            }
        }
    }

    public struct Day: Identifiable, Equatable, Sendable {
        public var date: Date
        public var runs: [BackupRun]
        public var id: Date { date }
    }

    /// Runs matching `filter` and `search` (file names, locations and reasons of
    /// missed items, or the failure reason), newest first, grouped by day.
    public static func days(
        from runs: [BackupRun],
        filter: Filter = .all,
        search: String = "",
        calendar: Calendar = .current
    ) -> [Day] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = runs
            .filter(filter.matches)
            .filter { query.isEmpty || matchesSearch($0, query) }
            .sorted { $0.startedAt > $1.startedAt }

        var days: [Day] = []
        for run in matching {
            let day = calendar.startOfDay(for: run.startedAt)
            if days.last?.date == day {
                days[days.count - 1].runs.append(run)
            } else {
                days.append(Day(date: day, runs: [run]))
            }
        }
        return days
    }

    static func matchesSearch(_ run: BackupRun, _ query: String) -> Bool {
        let haystack = run.missedItems.flatMap { [$0.name, $0.location, $0.reason] } + [run.failureReason ?? ""]
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
