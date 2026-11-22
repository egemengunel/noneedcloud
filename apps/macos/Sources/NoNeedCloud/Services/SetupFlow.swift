import Combine
import Foundation

enum DestinationProvider: String, CaseIterable, Identifiable, Sendable {
    case folder, s3, onedrive, gdrive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder: "Local or NAS Folder"
        case .s3: "S3-Compatible Cloud"
        case .onedrive: "OneDrive"
        case .gdrive: "Google Drive"
        }
    }
}

final class SetupFlow: ObservableObject {
    enum Step: Int, Sendable, Equatable {
        case sources = 1
        case destination = 2
        case startBackup = 3

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    static let defaultPlanName = "My First Backup"

    @Published private(set) var step: Step = .sources
    @Published var sourceFolderURLs: [URL] = []
    @Published var includeICloudDrive = false
    @Published var includePages = false
    @Published var includeNumbers = false
    @Published var includePhotos = false
    @Published var photosOnly = false
    @Published var videosOnly = false
    @Published var includeEdits = true
    @Published var includeSharedAlbums = false
    @Published var usePhotoDateRange = false
    @Published var photoDateRangeStart = Date.now
    @Published var photoDateRangeEnd = Date.now

    @Published var destinationProvider: DestinationProvider = .folder
    @Published var destinationURL: URL?
    @Published var s3Endpoint = ""
    @Published var s3Region = "us-east-1"
    @Published var s3Bucket = ""
    @Published var s3Prefix = ""
    @Published var s3AccessKeyID = ""
    @Published var s3SecretAccessKey = ""
    @Published var s3SessionToken = ""
    @Published var s3UsePathStyle = true
    @Published var cloudToken = ""
    @Published private(set) var destinationError: String?

    /// Set when editing an existing plan so its keychain reference is reused
    /// unless the user types a new secret.
    var existingDestination: Destination?
    var keychain: (any KeychainStore)?

    var plannedSources: [BackupSource] {
        var sources = sourceFolderURLs.map(BackupSource.folder)
        if includeICloudDrive { sources.append(.icloudDrive) }
        if includePages { sources.append(.pages) }
        if includeNumbers { sources.append(.numbers) }
        return sources
    }

    var plannedDestination: Destination? {
        switch destinationProvider {
        case .folder:
            return destinationURL.map(Destination.folder)
        case .s3:
            let endpoint = s3Endpoint.trimmingCharacters(in: .whitespaces)
            var endpointURL: URL?
            if !endpoint.isEmpty {
                guard let parsed = URL(string: endpoint),
                      let scheme = parsed.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return nil }
                endpointURL = parsed
            }
            guard !s3Bucket.trimmingCharacters(in: .whitespaces).isEmpty,
                  !s3Region.trimmingCharacters(in: .whitespaces).isEmpty,
                  !s3AccessKeyID.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let config = S3Config(
                endpointURL: endpointURL,
                region: s3Region.trimmingCharacters(in: .whitespaces),
                bucket: s3Bucket.trimmingCharacters(in: .whitespaces),
                prefix: s3Prefix.trimmingCharacters(in: .whitespaces),
                usePathStyle: s3UsePathStyle,
                accessKeyID: s3AccessKeyID.trimmingCharacters(in: .whitespaces),
                secretRef: existingS3Config?.secretRef ?? ""
            )
            guard !s3SecretAccessKey.isEmpty || !config.secretRef.isEmpty else { return nil }
            return .s3(config)
        case .onedrive:
            let secretRef = existingCloudSecretRef ?? ""
            guard !cloudToken.isEmpty || !secretRef.isEmpty else { return nil }
            return .onedrive(CloudTokenConfig(secretRef: secretRef))
        case .gdrive:
            let secretRef = existingCloudSecretRef ?? ""
            guard !cloudToken.isEmpty || !secretRef.isEmpty else { return nil }
            return .gdrive(CloudTokenConfig(secretRef: secretRef))
        }
    }

    var canContinue: Bool {
        switch step {
        case .sources: (includePhotos || !plannedSources.isEmpty) && !(photosOnly && videosOnly)
        case .destination: plannedDestination != nil
        case .startBackup: false
        }
    }

    func addSourceFolder(_ url: URL) {
        guard !sourceFolderURLs.contains(url) else { return }
        sourceFolderURLs.append(url)
    }

    func removeSourceFolder(_ url: URL) {
        sourceFolderURLs.removeAll { $0 == url }
    }

    @discardableResult
    func next() -> Bool {
        guard canContinue, let target = step.next else { return false }
        step = target
        return true
    }

    @discardableResult
    func back() -> Bool {
        guard let target = step.previous else { return false }
        step = target
        return true
    }

    func makePlan(name: String = SetupFlow.defaultPlanName) -> BackupPlan? {
        let sources = plannedSources
        guard !sources.isEmpty || includePhotos, var destination = plannedDestination else { return nil }
        destinationError = nil
        do {
            destination = try persistDestinationCredentials(destination)
        } catch {
            destinationError = error.localizedDescription
            return nil
        }
        return BackupPlan(
            name: name,
            sources: sources,
            includePhotos: includePhotos,
            photoOptions: PhotoOptions(
                fullTimeline: !(photosOnly || videosOnly),
                photosOnly: photosOnly,
                videosOnly: videosOnly,
                includeEdits: includeEdits,
                includeSharedAlbums: includeSharedAlbums,
                dateRangeStart: usePhotoDateRange ? photoDateRangeStart : nil,
                dateRangeEnd: usePhotoDateRange ? photoDateRangeEnd : nil
            ),
            destination: destination
        )
    }

    private var existingS3Config: S3Config? {
        if case .s3(let config) = existingDestination { return config }
        return nil
    }

    private var existingCloudSecretRef: String? {
        switch existingDestination {
        case .onedrive(let config), .gdrive(let config): config.secretRef
        default: nil
        }
    }

    private func persistDestinationCredentials(_ destination: Destination) throws -> Destination {
        switch destination {
        case .folder:
            return destination
        case .s3(var config):
            guard !s3SecretAccessKey.isEmpty else { return destination }
            if config.secretRef.isEmpty { config.secretRef = UUID().uuidString }
            let keychain = try requireKeychain()
            let secret = S3SecretPayload(
                secretAccessKey: s3SecretAccessKey,
                sessionToken: s3SessionToken.isEmpty ? nil : s3SessionToken
            )
            try keychain.save(Data(JSONEncoder().encode(secret)), account: config.secretRef)
            return .s3(config)
        case .onedrive(var config):
            guard !cloudToken.isEmpty else { return destination }
            if config.secretRef.isEmpty { config.secretRef = UUID().uuidString }
            try requireKeychain().save(Data(cloudToken.utf8), account: config.secretRef)
            return .onedrive(config)
        case .gdrive(var config):
            guard !cloudToken.isEmpty else { return destination }
            if config.secretRef.isEmpty { config.secretRef = UUID().uuidString }
            try requireKeychain().save(Data(cloudToken.utf8), account: config.secretRef)
            return .gdrive(config)
        }
    }

    private func requireKeychain() throws -> any KeychainStore {
        guard let keychain else {
            throw DestinationError("Keychain is unavailable, so the destination credentials could not be saved.")
        }
        return keychain
    }
}
