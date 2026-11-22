import Foundation

/// A file a run couldn't copy. It is retried on the next run.
public struct MissedItem: Codable, Equatable, Hashable, Sendable {
    /// File name, e.g. "IMG_2841.HEIC".
    public var name: String
    /// Where it lives, e.g. "iCloud Photos" or "iCloud Drive / Documents".
    public var location: String
    /// Plain-language reason, e.g. "The iCloud download stopped partway."
    public var reason: String

    public init(name: String, location: String, reason: String) {
        self.name = name
        self.location = location
        self.reason = reason
    }
}
