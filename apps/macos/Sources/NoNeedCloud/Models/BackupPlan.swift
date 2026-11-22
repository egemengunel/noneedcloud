import Foundation

struct PhotoOptions: Codable, Equatable, Sendable {
    var fullTimeline: Bool
}

struct BackupPlan: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sourceFolderURLs: [URL]
    var includePhotos: Bool
    var photoOptions: PhotoOptions
    var destinationURL: URL
    var schedule: Schedule = .manual
}
