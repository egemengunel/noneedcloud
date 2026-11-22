import Foundation

public struct PhotoOptions: Codable, Equatable, Sendable {
    public var fullTimeline: Bool

    public init(fullTimeline: Bool) {
        self.fullTimeline = fullTimeline
    }
}

public struct BackupPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceFolders: [FolderReference]
    public var includePhotos: Bool
    public var photoOptions: PhotoOptions
    public var destination: FolderReference
    public var schedule: Schedule

    public init(
        id: UUID = UUID(),
        name: String,
        sourceFolders: [FolderReference],
        includePhotos: Bool,
        photoOptions: PhotoOptions,
        destination: FolderReference,
        schedule: Schedule = .manual
    ) {
        self.id = id
        self.name = name
        self.sourceFolders = sourceFolders
        self.includePhotos = includePhotos
        self.photoOptions = photoOptions
        self.destination = destination
        self.schedule = schedule
    }
}
