import Foundation
@testable import NoNeedCloudCore

enum TestSupport {
    static func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("noneedcloud-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func withTempStore(_ body: (JSONPlanStore, URL) throws -> Void) throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(JSONPlanStore(directory: dir), dir)
    }

    /// A reference with placeholder bookmark bytes, for tests that never touch disk.
    static func folder(_ path: String) -> FolderReference {
        FolderReference(bookmark: Data(path.utf8), displayPath: path)
    }

    static func makePlan(
        name: String = "Test Plan",
        sources: [FolderReference] = [folder("/tmp/sources")],
        includePhotos: Bool = true,
        destination: FolderReference = folder("/tmp/dest")
    ) -> BackupPlan {
        BackupPlan(
            name: name,
            sourceFolders: sources,
            includePhotos: includePhotos,
            photoOptions: PhotoOptions(fullTimeline: true),
            destination: destination
        )
    }
}
