import Foundation
import Observation

@MainActor
@Observable
public final class SetupFlow {
    public enum Step: Int, Sendable, Equatable {
        case sources = 1
        case destination = 2
        case startBackup = 3

        public var next: Step? { Step(rawValue: rawValue + 1) }
        public var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    public static let defaultPlanName = "My First Backup"

    public private(set) var step: Step = .sources
    public private(set) var sourceFolders: [FolderReference] = []
    public var includePhotos = false
    public var destination: FolderReference?

    public init() {}

    public var canContinue: Bool {
        switch step {
        case .sources: includePhotos || !sourceFolders.isEmpty
        case .destination: destination != nil
        case .startBackup: false
        }
    }

    /// Folders are compared by path, so picking the same folder twice is a no-op.
    public func addSourceFolder(_ folder: FolderReference) {
        guard !sourceFolders.contains(where: { $0.displayPath == folder.displayPath }) else { return }
        sourceFolders.append(folder)
    }

    public func removeSourceFolder(_ folder: FolderReference) {
        sourceFolders.removeAll { $0.displayPath == folder.displayPath }
    }

    @discardableResult
    public func next() -> Bool {
        guard canContinue, let target = step.next else { return false }
        step = target
        return true
    }

    @discardableResult
    public func back() -> Bool {
        guard let target = step.previous else { return false }
        step = target
        return true
    }

    public func makePlan(name: String = SetupFlow.defaultPlanName) -> BackupPlan? {
        guard !sourceFolders.isEmpty || includePhotos, let destination else { return nil }
        return BackupPlan(
            name: name,
            sourceFolders: sourceFolders,
            includePhotos: includePhotos,
            photoOptions: PhotoOptions(fullTimeline: true),
            destination: destination
        )
    }
}
