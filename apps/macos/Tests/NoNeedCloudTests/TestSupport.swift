import Foundation
@testable import NoNeedCloud

enum TestSupport {
    static func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parachute-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func withTempStore(_ body: (JSONPlanStore, URL) throws -> Void) throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(JSONPlanStore(directory: dir), dir)
    }

    static func makePlan(
        name: String = "Test Plan",
        sources: [URL] = [URL(fileURLWithPath: "/tmp/sources")],
        includePhotos: Bool = false,
        photoOptions: PhotoOptions = PhotoOptions(),
        destination: URL = URL(fileURLWithPath: "/tmp/dest"),
        schedule: Schedule = .manual
    ) -> BackupPlan {
        BackupPlan(
            name: name,
            sourceFolderURLs: sources,
            includePhotos: includePhotos,
            photoOptions: photoOptions,
            destinationURL: destination,
            schedule: schedule
        )
    }

    static func makePlan(
        name: String = "Test Plan",
        sources: [URL] = [URL(fileURLWithPath: "/tmp/sources")],
        includePhotos: Bool = false,
        photoOptions: PhotoOptions = PhotoOptions(),
        destination: Destination,
        schedule: Schedule = .manual
    ) -> BackupPlan {
        BackupPlan(
            name: name,
            sources: sources.map(BackupSource.folder),
            includePhotos: includePhotos,
            photoOptions: photoOptions,
            destination: destination,
            schedule: schedule
        )
    }
}
