import Foundation

/// What to back up from the Photos library.
public struct PhotoSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var includePhotos: Bool
    public var includeVideos: Bool
    /// Also copy the edited rendition next to the original.
    public var includeEdits: Bool
    public var includeSharedAlbums: Bool

    public init(
        isEnabled: Bool = false,
        includePhotos: Bool = true,
        includeVideos: Bool = true,
        includeEdits: Bool = true,
        includeSharedAlbums: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.includePhotos = includePhotos
        self.includeVideos = includeVideos
        self.includeEdits = includeEdits
        self.includeSharedAlbums = includeSharedAlbums
    }

    public static let defaults = PhotoSettings()
}

/// Which folders to back up (iCloud Drive, app data, any folder).
public struct FolderSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var folders: [FolderReference]

    public init(isEnabled: Bool = false, folders: [FolderReference] = []) {
        self.isEnabled = isEnabled
        self.folders = folders
    }
}

/// When on, items deleted from the source are moved to `Deleted/` at the destination.
public struct MirroringSettings: Codable, Equatable, Sendable {
    public enum Retention: String, Codable, CaseIterable, Sendable {
        case forever, ninetyDays, thirtyDays, untilNextBackup
    }

    public var isEnabled: Bool
    public var retention: Retention

    public init(isEnabled: Bool = false, retention: Retention = .ninetyDays) {
        self.isEnabled = isEnabled
        self.retention = retention
    }
}

public struct ScheduleSettings: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case off, hourly, daily, weekly, monthly
    }

    public var frequency: Frequency
    /// Minutes after midnight for daily/weekly/monthly runs.
    public var timeOfDayMinutes: Int
    /// 1 = Sunday … 7 = Saturday (Calendar convention), used for weekly runs.
    public var weekday: Int
    /// 1…28, used for monthly runs.
    public var dayOfMonth: Int
    public var startAtLogin: Bool

    public init(
        frequency: Frequency = .off,
        timeOfDayMinutes: Int = 2 * 60,
        weekday: Int = 1,
        dayOfMonth: Int = 1,
        startAtLogin: Bool = false
    ) {
        self.frequency = frequency
        self.timeOfDayMinutes = timeOfDayMinutes
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.startAtLogin = startAtLogin
    }

    /// The next time a scheduled backup is due after `date`, or nil when off.
    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        let hour = timeOfDayMinutes / 60, minute = timeOfDayMinutes % 60
        switch frequency {
        case .off:
            return nil
        case .hourly:
            return calendar.nextDate(after: date, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
        case .daily:
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
        case .weekly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                matchingPolicy: .nextTime
            )
        case .monthly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(day: dayOfMonth, hour: hour, minute: minute),
                matchingPolicy: .nextTime
            )
        }
    }
}

public struct BackupPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var photos: PhotoSettings
    public var files: FolderSettings
    public var mirroring: MirroringSettings
    public var destination: FolderReference?
    /// Last known details of the destination volume (see `DestinationDetails`).
    public var destinationDetails: DestinationDetails?
    public var schedule: ScheduleSettings

    public init(
        id: UUID = UUID(),
        name: String = BackupPlan.defaultName,
        photos: PhotoSettings = .defaults,
        files: FolderSettings = FolderSettings(),
        mirroring: MirroringSettings = MirroringSettings(),
        destination: FolderReference? = nil,
        destinationDetails: DestinationDetails? = nil,
        schedule: ScheduleSettings = ScheduleSettings()
    ) {
        self.id = id
        self.name = name
        self.photos = photos
        self.files = files
        self.mirroring = mirroring
        self.destination = destination
        self.destinationDetails = destinationDetails
        self.schedule = schedule
    }

    public static let defaultName = "My Backup"

    /// At least one source is switched on and has something to back up.
    public var hasSources: Bool {
        photos.isEnabled || (files.isEnabled && !files.folders.isEmpty)
    }

    public var isReadyToRun: Bool {
        hasSources && destination != nil
    }
}
