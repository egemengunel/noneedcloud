import Foundation
import Testing
@testable import NoNeedCloudCore

struct FolderReferenceTests {
    @Test func bookmarkResolvesBackToSameFolder() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let reference = try FolderReference(url: dir)
        let resolved = try reference.resolve()

        #expect(resolved.url.standardizedFileURL.resolvingSymlinksInPath()
            == dir.standardizedFileURL.resolvingSymlinksInPath())
        #expect(reference.displayName == dir.lastPathComponent)
    }

    @Test func bookmarkFollowsFolderAfterRename() throws {
        let parent = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = parent.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)

        let reference = try FolderReference(url: original)
        let renamed = parent.appendingPathComponent("Renamed Backups", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolved = try reference.resolve()
        #expect(resolved.url.lastPathComponent == "Renamed Backups")
    }

    @Test func withAccessRunsBodyWithResolvedURL() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("hi".utf8).write(to: dir.appendingPathComponent("note.txt"))

        let names = try FolderReference(url: dir).withAccess { url in
            try FileManager.default.contentsOfDirectory(atPath: url.path)
        }
        #expect(names == ["note.txt"])
    }

    @Test func garbageBookmarkThrows() {
        let reference = TestSupport.folder("/nowhere")
        #expect(throws: (any Error).self) { try reference.resolve() }
    }

    @Test func planWithBookmarksRoundTripsThroughStore() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestSupport.withTempStore { store, _ in
            let plan = TestSupport.makePlan(sources: [try FolderReference(url: dir)])
            try store.savePlans([plan])
            #expect(try store.loadPlans() == [plan])
        }
    }
}
