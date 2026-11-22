import Combine
import Foundation

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
    @Published var destinationURL: URL?

    var plannedSources: [BackupSource] {
        var sources = sourceFolderURLs.map(BackupSource.folder)
        if includeICloudDrive { sources.append(.icloudDrive) }
        if includePages { sources.append(.pages) }
        if includeNumbers { sources.append(.numbers) }
        return sources
    }

    var canContinue: Bool {
        switch step {
        case .sources: (includePhotos || !plannedSources.isEmpty) && !(photosOnly && videosOnly)
        case .destination: destinationURL != nil
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
        guard !sources.isEmpty || includePhotos, let destinationURL else { return nil }
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
            destinationURL: destinationURL
        )
    }
}
