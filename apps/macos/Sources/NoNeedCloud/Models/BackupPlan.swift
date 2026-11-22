import Foundation

enum BackupSource: Hashable, Sendable {
    case folder(URL)
    case icloudDrive
    case appContainer(bundleID: String, displayName: String)

    static let pages = BackupSource.appContainer(bundleID: "com.apple.iWork.Pages", displayName: "Pages")
    static let numbers = BackupSource.appContainer(bundleID: "com.apple.iWork.Numbers", displayName: "Numbers")

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
        case .appContainer(let bundleID, _): ICloudDriveSource.containerURL(bundleID: bundleID)
        }
    }
}

extension BackupSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, url, bundleID, displayName
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
                bundleID: try container.decode(String.self, forKey: .bundleID),
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
        case .appContainer(let bundleID, let displayName):
            try container.encode(Kind.appContainer, forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
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
    var destinationURL: URL
    var schedule: Schedule = .manual

    enum CodingKeys: String, CodingKey {
        case id, name, sources
        case legacySourceFolderURLs = "sourceFolderURLs"
        case includePhotos
        case photoOptions
        case destinationURL
        case schedule
    }

    init(
        name: String,
        sources: [BackupSource],
        includePhotos: Bool,
        photoOptions: PhotoOptions,
        destinationURL: URL,
        schedule: Schedule = .manual
    ) {
        self.name = name
        self.sources = sources
        self.includePhotos = includePhotos
        self.photoOptions = photoOptions
        self.destinationURL = destinationURL
        self.schedule = schedule
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
            destinationURL: destinationURL,
            schedule: schedule
        )
    }

    var sourceFolderURLs: [URL] {
        sources.compactMap {
            if case .folder(let url) = $0 { return url }
            return nil
        }
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
        destinationURL = try container.decode(URL.self, forKey: .destinationURL)
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule) ?? .manual
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sources, forKey: .sources)
        try container.encode(includePhotos, forKey: .includePhotos)
        try container.encode(photoOptions, forKey: .photoOptions)
        try container.encode(destinationURL, forKey: .destinationURL)
        try container.encode(schedule, forKey: .schedule)
    }
}
