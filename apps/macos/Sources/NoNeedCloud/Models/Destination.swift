import Foundation

struct S3Config: Codable, Hashable, Sendable {
    var endpointURL: URL?
    var region: String
    var bucket: String
    var prefix: String
    var usePathStyle: Bool
    var accessKeyID: String
    var secretRef: String

    var effectiveEndpoint: URL {
        endpointURL ?? URL(string: "https://s3.\(region).amazonaws.com") ?? URL(string: "https://s3.amazonaws.com")!
    }
}

struct CloudTokenConfig: Codable, Hashable, Sendable {
    var secretRef: String
}

enum Destination: Hashable, Sendable {
    case folder(URL)
    case s3(S3Config)
    case onedrive(CloudTokenConfig)
    case gdrive(CloudTokenConfig)

    var displayName: String {
        switch self {
        case .folder(let url): url.path(percentEncoded: false)
        case .s3(let config): "S3: \(config.bucket)"
        case .onedrive: "OneDrive"
        case .gdrive: "Google Drive"
        }
    }

    var indexKey: String {
        switch self {
        case .folder(let url): url.path(percentEncoded: false)
        case .s3(let config): "s3://\(config.effectiveEndpoint.host ?? "")/\(config.bucket)/\(config.prefix)"
        case .onedrive(let config): "onedrive/\(config.secretRef)"
        case .gdrive(let config): "gdrive/\(config.secretRef)"
        }
    }

    var indexNameComponent: String {
        switch self {
        case .folder(let url): url.lastPathComponent
        case .s3(let config): "s3-\(config.bucket)"
        case .onedrive: "OneDrive"
        case .gdrive: "GoogleDrive"
        }
    }

    func makeDestination(keychain: any KeychainStore, httpClient: any HTTPClient) -> any BackupDestination {
        switch self {
        case .folder(let url): LocalFolderDestination(rootURL: url)
        case .s3(let config): S3Destination(config: config, keychain: keychain, httpClient: httpClient)
        case .onedrive(let config): OneDriveDestination(config: config, keychain: keychain, httpClient: httpClient)
        case .gdrive(let config): GoogleDriveDestination(config: config, keychain: keychain, httpClient: httpClient)
        }
    }
}

extension Destination: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, url, s3, onedrive, gdrive
    }

    private enum Kind: String, Codable {
        case folder, s3, onedrive, gdrive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .folder:
            self = .folder(try container.decode(URL.self, forKey: .url))
        case .s3:
            self = .s3(try container.decode(S3Config.self, forKey: .s3))
        case .onedrive:
            self = .onedrive(try container.decode(CloudTokenConfig.self, forKey: .onedrive))
        case .gdrive:
            self = .gdrive(try container.decode(CloudTokenConfig.self, forKey: .gdrive))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let url):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .s3(let config):
            try container.encode(Kind.s3, forKey: .kind)
            try container.encode(config, forKey: .s3)
        case .onedrive(let config):
            try container.encode(Kind.onedrive, forKey: .kind)
            try container.encode(config, forKey: .onedrive)
        case .gdrive(let config):
            try container.encode(Kind.gdrive, forKey: .kind)
            try container.encode(config, forKey: .gdrive)
        }
    }
}
