import Foundation

/// Pure retention rules for the Deleted folder. Given the top-level date
/// folder names ("YYYY-MM-DD"), the run date, and the retention setting,
/// returns the folders that should be purged.
enum RetentionPolicy {
    /// - `forever`: never purges.
    /// - `days(n)`: purges folders dated before `n` days ago (day-precision,
    ///   so calendar and month boundaries are handled by the calendar).
    /// - `untilNextBackup`: purges everything except the current run's date
    ///   folder, which keeps this run's own moves.
    static func foldersToPurge(
        folderNames: [String],
        runDate: Date,
        retention: Retention,
        calendar: Calendar = .current
    ) -> [String] {
        switch retention {
        case .forever:
            return []
        case .days(let requestedDays):
            let days = max(requestedDays, 0)
            guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: runDate)) else {
                return []
            }
            return folderNames.filter { name in
                guard let folderDay = folderDate(for: name, calendar: calendar) else { return false }
                return folderDay < cutoff
            }
        case .untilNextBackup:
            let current = folderName(for: runDate, calendar: calendar)
            return folderNames.filter { $0 != current }
        }
    }

    static func folderName(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func folderDate(for name: String, calendar: Calendar = .current) -> Date? {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), year > 0,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}
