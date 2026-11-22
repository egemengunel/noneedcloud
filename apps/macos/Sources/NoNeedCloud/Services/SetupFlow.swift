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
    @Published var includePhotos = false
    @Published var destinationURL: URL?

    var canContinue: Bool {
        switch step {
        case .sources: includePhotos || !sourceFolderURLs.isEmpty
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
        guard !sourceFolderURLs.isEmpty || includePhotos, let destinationURL else { return nil }
        return BackupPlan(
            name: name,
            sourceFolderURLs: sourceFolderURLs,
            includePhotos: includePhotos,
            photoOptions: PhotoOptions(fullTimeline: true),
            destinationURL: destinationURL
        )
    }
}
