import Foundation

struct PhotoOptions: Codable, Equatable, Sendable {
    var fullTimeline = true
    var photosOnly = false
    var videosOnly = false
    var includeEdits = true
    var includeSharedAlbums = false
    var dateRangeStart: Date?
    var dateRangeEnd: Date?

    init(
        fullTimeline: Bool = true,
        photosOnly: Bool = false,
        videosOnly: Bool = false,
        includeEdits: Bool = true,
        includeSharedAlbums: Bool = false,
        dateRangeStart: Date? = nil,
        dateRangeEnd: Date? = nil
    ) {
        self.fullTimeline = fullTimeline
        self.photosOnly = photosOnly
        self.videosOnly = videosOnly
        self.includeEdits = includeEdits
        self.includeSharedAlbums = includeSharedAlbums
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullTimeline = try container.decodeIfPresent(Bool.self, forKey: .fullTimeline) ?? true
        photosOnly = try container.decodeIfPresent(Bool.self, forKey: .photosOnly) ?? false
        videosOnly = try container.decodeIfPresent(Bool.self, forKey: .videosOnly) ?? false
        includeEdits = try container.decodeIfPresent(Bool.self, forKey: .includeEdits) ?? true
        includeSharedAlbums = try container.decodeIfPresent(Bool.self, forKey: .includeSharedAlbums) ?? false
        dateRangeStart = try container.decodeIfPresent(Date.self, forKey: .dateRangeStart)
        dateRangeEnd = try container.decodeIfPresent(Date.self, forKey: .dateRangeEnd)
    }
}
