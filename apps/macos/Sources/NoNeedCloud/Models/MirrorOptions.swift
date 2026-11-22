import Foundation

/// How long mirrored deletions are kept in the destination's Deleted folder.
enum Retention: Codable, Hashable, Sendable {
    case forever
    case days(Int)
    case untilNextBackup

    var summary: String {
        switch self {
        case .forever: "Forever"
        case .days(let days): "\(days) days"
        case .untilNextBackup: "Until next backup"
        }
    }
}

/// Optional per-plan mirroring: when enabled, items deleted from the source
/// since the last run are moved to `Deleted/<date>/…` instead of silently
/// disappearing from the destination. Off by default (backup only grows).
struct MirrorOptions: Codable, Equatable, Sendable {
    var enabled: Bool
    var retention: Retention

    static let disabled = MirrorOptions(enabled: false, retention: .days(90))

    init(enabled: Bool = false, retention: Retention = .days(90)) {
        self.enabled = enabled
        self.retention = retention
    }

    var stateSummary: String {
        enabled ? "On · \(retention.summary)" : "Off"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        retention = try container.decodeIfPresent(Retention.self, forKey: .retention) ?? .days(90)
    }
}
