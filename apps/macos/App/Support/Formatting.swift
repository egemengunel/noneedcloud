import Foundation
import NoNeedCloudCore
import SwiftUI

enum Formatting {
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func items(_ value: Int) -> String {
        value == 1 ? String(localized: "1 item") : String(localized: "\(count(value)) items")
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "just now") }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// "About 3 min", "About 2 h 10 min", "Less than a minute".
    static func remaining(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(localized: "Less than a minute left") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.day, .hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        return String(localized: "About \(formatter.string(from: interval) ?? "") left")
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "–"
    }

    /// "Photos and iCloud Drive", "Photos and 2 folders", "Projects".
    static func sourcesSummary(_ plan: BackupPlan) -> String {
        var parts: [String] = []
        if plan.photos.isEnabled { parts.append(String(localized: "Photos")) }
        if plan.files.isEnabled, !plan.files.folders.isEmpty {
            let folders = plan.files.folders
            if folders.count == 1 {
                parts.append(folderName(folders[0]))
            } else {
                parts.append(String(localized: "\(folders.count) folders"))
            }
        }
        if parts.isEmpty { return String(localized: "Nothing selected") }
        return parts.count == 2 ? String(localized: "\(parts[0]) and \(parts[1])") : parts[0]
    }

    /// iCloud Drive's container shows as "iCloud Drive" rather than "Mobile Documents".
    static func folderName(_ folder: FolderReference) -> String {
        if folder.displayPath.hasSuffix("/Library/Mobile Documents/com~apple~CloudDocs") { return "iCloud Drive" }
        return folder.displayName
    }

    static func isICloud(_ folder: FolderReference) -> Bool {
        folder.displayPath.contains("/Library/Mobile Documents")
    }

    /// "today at 09:18", "yesterday at 22:51", "on 12 Sep at 10:00".
    static func dayAndTime(_ date: Date, now: Date = .now) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today at \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "yesterday at \(time)")
        }
        return String(localized: "on \(date.formatted(.dateTime.day().month(.abbreviated))) at \(time)")
    }

    /// "Today, 09:18", "Yesterday, 22:51", "12 Sep, 10:00".
    static func dayCommaTime(_ date: Date, now: Date = .now) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today, \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(time)")
        }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))), \(time)"
    }

    /// "Tonight, 23:00", "Tomorrow, 02:00", "Monday, 02:00".
    static func nextRun(_ date: Date, now: Date = .now) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 18
                ? String(localized: "Tonight, \(time)") : String(localized: "Today, \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow, \(time)")
        }
        return "\(date.formatted(.dateTime.weekday(.wide))), \(time)"
    }

    /// "Every day", "Every hour", "Mondays", "Monthly".
    static func frequency(_ schedule: ScheduleSettings) -> String {
        switch schedule.frequency {
        case .off: String(localized: "Manual")
        case .hourly: String(localized: "Every hour")
        case .daily: String(localized: "Every day")
        case .weekly: String(localized: "Every week")
        case .monthly: String(localized: "Every month")
        }
    }

    /// "Network storage · SMB", "External disk", "This Mac".
    static func kind(_ details: DestinationDetails?) -> String {
        guard let details else { return String(localized: "Folder") }
        switch details.kind {
        case .network:
            let base = String(localized: "Network storage")
            return details.networkProtocol.map { "\(base)  ·  \($0)" } ?? base
        case .externalDisk: return String(localized: "External disk")
        case .internalDisk: return String(localized: "This Mac")
        }
    }

    static func kindSymbol(_ details: DestinationDetails?) -> String {
        switch details?.kind {
        case .internalDisk: "internaldrive"
        case .network, .externalDisk, nil: "externaldrive"
        }
    }

    static func schedule(_ schedule: ScheduleSettings) -> String {
        let time = timeOfDay(schedule.timeOfDayMinutes)
        switch schedule.frequency {
        case .off: return String(localized: "Manual")
        case .hourly: return String(localized: "Every hour")
        case .daily: return String(localized: "Daily at \(time)")
        case .weekly:
            let day = Calendar.current.weekdaySymbols[(schedule.weekday - 1).clamped(to: 0...6)]
            return String(localized: "Every \(day) at \(time)")
        case .monthly: return String(localized: "Monthly on day \(schedule.dayOfMonth) at \(time)")
        }
    }

    static func timeOfDay(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func retention(_ retention: MirroringSettings.Retention) -> String {
        switch retention {
        case .forever: String(localized: "Keep forever")
        case .ninetyDays: String(localized: "Keep for 90 days")
        case .thirtyDays: String(localized: "Keep for 30 days")
        case .untilNextBackup: String(localized: "Remove at next backup")
        }
    }

    static func stage(_ stage: BackupProgress.Stage, kind: BackupProgress.SourceKind, destination: String) -> String {
        switch stage {
        case .check: String(localized: "Comparing with \(destination)")
        case .fetch: kind == .photo ? String(localized: "Downloading from iCloud") : String(localized: "Making the file available")
        case .write: String(localized: "Copying to \(destination)")
        case .release: String(localized: "Freeing up space on this Mac")
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
