import Foundation
import NoNeedCloudCore
import SwiftUI

enum Formatting {
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func items(_ value: Int) -> String {
        value == 1 ? "1 item" : "\(count(value)) items"
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// "About 3 min", "About 2 h 10 min", "Less than a minute".
    static func remaining(_ interval: TimeInterval) -> String {
        if interval < 60 { return "Less than a minute left" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.day, .hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return "About \(formatter.string(from: interval) ?? "") left"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "–"
    }

    /// "Photos and 2 folders", "Photos", "1 folder".
    static func sourcesSummary(_ plan: BackupPlan) -> String {
        var parts: [String] = []
        if plan.photos.isEnabled { parts.append("Photos") }
        if plan.files.isEnabled, !plan.files.folders.isEmpty {
            let count = plan.files.folders.count
            parts.append(count == 1 ? "1 folder" : "\(count) folders")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " and ")
    }

    static func schedule(_ schedule: ScheduleSettings) -> String {
        let time = timeOfDay(schedule.timeOfDayMinutes)
        switch schedule.frequency {
        case .off: return "Off"
        case .hourly: return "Every hour"
        case .daily: return "Daily at \(time)"
        case .weekly:
            let day = Calendar.current.weekdaySymbols[(schedule.weekday - 1).clamped(to: 0...6)]
            return "\(day)s at \(time)"
        case .monthly: return "Monthly on day \(schedule.dayOfMonth) at \(time)"
        }
    }

    static func timeOfDay(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func retention(_ retention: MirroringSettings.Retention) -> String {
        switch retention {
        case .forever: "Keep forever"
        case .ninetyDays: "Keep for 90 days"
        case .thirtyDays: "Keep for 30 days"
        case .untilNextBackup: "Remove at next backup"
        }
    }

    static func stage(_ stage: BackupProgress.Stage) -> String {
        switch stage {
        case .check: "Checking"
        case .fetch: "Downloading"
        case .write: "Copying"
        case .release: "Freeing space"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension AppModel {
    /// A binding that edits one field of the plan and persists it.
    func planBinding<Value>(_ keyPath: WritableKeyPath<BackupPlan, Value>) -> Binding<Value> {
        Binding(
            get: { self.plan[keyPath: keyPath] },
            set: { newValue in self.updatePlan { $0[keyPath: keyPath] = newValue } }
        )
    }
}
