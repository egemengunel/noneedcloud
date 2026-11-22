import Foundation

enum BackupSource: Hashable, Sendable {
    case folder(URL)
    case icloudDrive
    case appContainer(groupID: String, displayName: String)

    static let pages = BackupSource.appContainer(groupID: "com~apple~Pages", displayName: "Pages")
    static let numbers = BackupSource.appContainer(groupID: "com~apple~Numbers", displayName: "Numbers")

    var displayName: String {
        switch self {
        case .folder(let url): url.lastPathComponent
        case .icloudDrive: "iCloud Drive"
        case .appContainer(_, let displayName): displayName
        }
    }

    var sourceURL: URL {
        switch self {
        case .folder(let url): url
        case .icloudDrive: ICloudDriveSource.cloudDocsRootURL
        case .appContainer(let groupID, _): ICloudDriveSource.appContainerDocumentsURL(
            groupID: groupID,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        }
    }
}

extension BackupSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, url
        case groupID = "bundleID"
        case displayName
    }

    private enum Kind: String, Codable {
        case folder, icloudDrive, appContainer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .folder:
            self = .folder(try container.decode(URL.self, forKey: .url))
        case .icloudDrive:
            self = .icloudDrive
        case .appContainer:
            self = .appContainer(
                groupID: try container.decode(String.self, forKey: .groupID),
                displayName: try container.decode(String.self, forKey: .displayName)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let url):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .icloudDrive:
            try container.encode(Kind.icloudDrive, forKey: .kind)
        case .appContainer(let groupID, let displayName):
            try container.encode(Kind.appContainer, forKey: .kind)
            try container.encode(groupID, forKey: .groupID)
            try container.encode(displayName, forKey: .displayName)
        }
    }
}

struct BackupPlan: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sources: [BackupSource]
    var includePhotos: Bool
    var photoOptions: PhotoOptions
    var destination: Destination
    var schedule: Schedule = .manual
    var mirrorOptions = MirrorOptions()

    enum CodingKeys: String, CodingKey {
        case id, name, sources
        case legacySourceFolderURLs = "sourceFolderURLs"
        case includePhotos
        case photoOptions
        case destination
        case legacyDestinationURL = "destinationURL"
        case schedule
        case mirrorOptions
    }

    init(
        name: String,
        sources: [BackupSource],
        includePhotos: Bool,
        photoOptions: PhotoOptions,
        destination: Destination,
        schedule: Schedule = .manual,
        mirrorOptions: MirrorOptions = MirrorOptions()
    ) {
        self.name = name
        self.sources = sources
        self.includePhotos = includePhotos
        self.photoOptions = photoOptions
        self.destination = destination
        self.schedule = schedule
        self.mirrorOptions = mirrorOptions
    }

    init(
        name: String,
        sources: [BackupSource],
        includePhotos: Bool,
        photoOptions: PhotoOptions,
        destinationURL: URL,
        schedule: Schedule = .manual
    ) {
        self.init(
            name: name,
            sources: sources,
            includePhotos: includePhotos,
            photoOptions: photoOptions,
            destination: .folder(destinationURL),
            schedule: schedule
        )
    }

    init(
        name: String,
        sourceFolderURLs: [URL],
        includePhotos: Bool,
        photoOptions: PhotoOptions,
        destinationURL: URL,
        schedule: Schedule = .manual
    ) {
        self.init(
            name: name,
            sources: sourceFolderURLs.map(BackupSource.folder),
            includePhotos: includePhotos,
            photoOptions: photoOptions,
            destination: .folder(destinationURL),
            schedule: schedule
        )
    }

    var sourceFolderURLs: [URL] {
        sources.compactMap {
            if case .folder(let url) = $0 { return url }
            return nil
        }
    }

    var destinationURL: URL? {
        if case .folder(let url) = destination { return url }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let decoded = try? container.decode([BackupSource].self, forKey: .sources) {
            sources = decoded
        } else {
            sources = try container.decode([URL].self, forKey: .legacySourceFolderURLs).map(BackupSource.folder)
        }
        includePhotos = try container.decode(Bool.self, forKey: .includePhotos)
        photoOptions = try container.decode(PhotoOptions.self, forKey: .photoOptions)
        if let decoded = try container.decodeIfPresent(Destination.self, forKey: .destination) {
            destination = decoded
        } else {
            destination = .folder(try container.decode(URL.self, forKey: .legacyDestinationURL))
        }
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule) ?? .manual
        mirrorOptions = try container.decodeIfPresent(MirrorOptions.self, forKey: .mirrorOptions) ?? MirrorOptions()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sources, forKey: .sources)
        try container.encode(includePhotos, forKey: .includePhotos)
        try container.encode(photoOptions, forKey: .photoOptions)
        try container.encode(destination, forKey: .destination)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(mirrorOptions, forKey: .mirrorOptions)
    }
}
