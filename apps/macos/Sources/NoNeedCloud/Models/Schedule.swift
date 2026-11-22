import Foundation

enum Schedule: Equatable, Sendable {
    case manual
    case hourly
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)
}

extension Schedule: Codable {
    private enum Kind: String, Codable {
        case hourly, daily, weekly, monthly
    }

    private enum CodingKeys: String, CodingKey {
        case kind, hour, minute, weekday, day
    }

    /// Legacy plans stored `.manual` as the plain string "manual"; scheduled
    /// values use a keyed object ("kind" plus time fields).
    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let legacy = try? singleValue.decode(String.self) {
            guard legacy == "manual" else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown schedule encoding: \(legacy)"
                ))
            }
            self = .manual
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .hourly:
            self = .hourly
        case .daily:
            self = .daily(
                hour: try container.decode(Int.self, forKey: .hour),
                minute: try container.decode(Int.self, forKey: .minute)
            )
        case .weekly:
            self = .weekly(
                weekday: try container.decode(Int.self, forKey: .weekday),
                hour: try container.decode(Int.self, forKey: .hour),
                minute: try container.decode(Int.self, forKey: .minute)
            )
        case .monthly:
            self = .monthly(
                day: try container.decode(Int.self, forKey: .day),
                hour: try container.decode(Int.self, forKey: .hour),
                minute: try container.decode(Int.self, forKey: .minute)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .manual:
            var container = encoder.singleValueContainer()
            try container.encode("manual")
        case .hourly:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.hourly, forKey: .kind)
        case .daily(let hour, let minute):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.daily, forKey: .kind)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .weekly(let weekday, let hour, let minute):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.weekly, forKey: .kind)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .monthly(let day, let hour, let minute):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.monthly, forKey: .kind)
            try container.encode(day, forKey: .day)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        }
    }
}

extension Schedule {
    var isScheduled: Bool {
        if case .manual = self { return false }
        return true
    }

    var summary: String {
        switch self {
        case .manual:
            "Manual"
        case .hourly:
            "Every hour"
        case .daily(let hour, let minute):
            "Daily at \(timeText(hour: hour, minute: minute))"
        case .weekly(let weekday, let hour, let minute):
            "Every \(weekdayName(weekday)) at \(timeText(hour: hour, minute: minute))"
        case .monthly(let day, let hour, let minute):
            "Monthly on day \(day) at \(timeText(hour: hour, minute: minute))"
        }
    }

    private func timeText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func weekdayName(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "day \(weekday)" }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }
}
