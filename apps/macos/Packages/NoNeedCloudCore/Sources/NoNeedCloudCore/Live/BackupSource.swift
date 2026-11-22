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

