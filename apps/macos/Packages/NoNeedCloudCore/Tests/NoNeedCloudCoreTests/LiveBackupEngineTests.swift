import Foundation
import Testing
@testable import NoNeedCloudCore

@MainActor
struct LiveBackupEngineTests {
    private func write(_ text: String, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func collect(_ engine: LiveBackupEngine, _ plan: BackupPlan) async throws -> [BackupProgress] {
        var updates: [BackupProgress] = []
        for try await update in engine.run(plan) { updates.append(update) }
        return updates
    }

    private func photoSource() -> MockPhotoLibrarySource {
        let source = MockPhotoLibrarySource(assets: [
            PhotoTestFixtures.asset(id: "a", filename: "IMG_0001.HEIC", creation: PhotoTestClock.date(2024, 5, 3)),
            PhotoTestFixtures.asset(id: "b", filename: "IMG_0002.MOV", creation: PhotoTestClock.date(2025, 1, 9), isPhoto: false, isVideo: true),
        ])
        source.addData(assetId: "a", component: PhotoTestFixtures.component(.original, "IMG_0001.HEIC", size: 5), Data("photo".utf8))
        source.addData(assetId: "b", component: PhotoTestFixtures.component(.original, "IMG_0002.MOV", size: 5), Data("video".utf8))
        return source
    }

    private struct Fixture {
        var root: URL
        var source: URL
        var destination: URL
        var engine: LiveBackupEngine
        var plan: BackupPlan
    }

    private func fixture(photos: Bool, library: MockPhotoLibrarySource? = nil) throws -> Fixture {
        let root = TestSupport.makeTempDirectory()
        let source = root.appendingPathComponent("Documents", isDirectory: true)
        let destination = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("one", to: "a.txt", in: source)
        try write("two", to: "Sub/b.txt", in: source)
        try write("three", to: "Sub/Deeper/c.txt", in: source)
        let library = library ?? photoSource()
        let engine = LiveBackupEngine(
            stateDirectory: root.appendingPathComponent("State", isDirectory: true),
            photoSource: { library }
        )
        let plan = BackupPlan(
            photos: PhotoSettings(isEnabled: photos),
            files: FolderSettings(isEnabled: true, folders: [try FolderReference(url: source)]),
            destination: try FolderReference(url: destination)
        )
        return Fixture(root: root, source: source, destination: destination, engine: engine, plan: plan)
    }

    @Test func copiesFoldersUnderTheirNameAndFinishes() async throws {
        let f = try fixture(photos: false)
        defer { try? FileManager.default.removeItem(at: f.root) }

        let updates = try await collect(f.engine, f.plan)
        let last = try #require(updates.last)

        #expect(last.phase == .finished)
        #expect(last.totalItems == 3)
        #expect(last.processedFiles == 3)
        #expect(last.copiedItems == 3)
        #expect(last.failedItems == 0)
        #expect(last.bytesWritten == 11)
        #expect(try String(contentsOf: f.destination.appendingPathComponent("Documents/Sub/Deeper/c.txt"), encoding: .utf8) == "three")
        #expect(updates.contains { $0.currentItem?.kind == .file })
    }

    @Test func secondRunSkipsUnchangedFilesButStillCountsThemProtected() async throws {
        let f = try fixture(photos: false)
        defer { try? FileManager.default.removeItem(at: f.root) }

        _ = try await collect(f.engine, f.plan)
        try write("new", to: "d.txt", in: f.source)
        let last = try #require(try await collect(f.engine, f.plan).last)

        #expect(last.phase == .finished)
        #expect(last.processedFiles == 4)
        #expect(last.copiedItems == 1)
        #expect(last.bytesWritten == 3)
    }

    @Test func backsUpPhotosIntoDayFoldersBeforeFiles() async throws {
        let f = try fixture(photos: true)
        defer { try? FileManager.default.removeItem(at: f.root) }

        let updates = try await collect(f.engine, f.plan)
        let last = try #require(updates.last)

        #expect(last.phase == .finished)
        #expect(last.processedPhotos == 2)
        #expect(last.processedFiles == 3)
        #expect(last.totalItems == 5)
        #expect(FileManager.default.fileExists(atPath: f.destination.appendingPathComponent("Photos/2024/05/03/IMG_0001.HEIC").path))
        #expect(FileManager.default.fileExists(atPath: f.destination.appendingPathComponent("Photos/2025/01/09/IMG_0002.MOV").path))
        // Total is unknown while the library is being planned.
        #expect(updates.first?.totalItems == nil)
        let firstFile = try #require(updates.firstIndex { $0.currentItem?.kind == .file })
        #expect(updates[..<firstFile].contains { $0.currentItem?.kind == .photo })
    }

    @Test func photosOnlySkipsVideos() async throws {
        var f = try fixture(photos: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.plan.photos.includeVideos = false
        f.plan.files.isEnabled = false

        let last = try #require(try await collect(f.engine, f.plan).last)

        #expect(last.processedPhotos == 1)
        #expect(!FileManager.default.fileExists(atPath: f.destination.appendingPathComponent("Photos/2025/01/09/IMG_0002.MOV").path))
    }

    @Test func failedPhotoExportBecomesAMissedItem() async throws {
        let library = photoSource()
        library.failExport = true
        var f = try fixture(photos: true, library: library)
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.plan.files.isEnabled = false

        let last = try #require(try await collect(f.engine, f.plan).last)

        #expect(last.phase == .finished)
        #expect(last.failedItems == 2)
        #expect(last.missedItems.map(\.name).sorted() == ["IMG_0001.HEIC", "IMG_0002.MOV"])
        #expect(last.missedItems.allSatisfy { $0.location == "iCloud Photos" })
    }

    @Test func missingDestinationThrows() async throws {
        let f = try fixture(photos: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.removeItem(at: f.destination)

        await #expect(throws: LiveBackupError.destinationUnavailable) {
            _ = try await collect(f.engine, f.plan)
        }
    }

    @Test func runsThroughAppModelAndRecordsTheRun() async throws {
        let f = try fixture(photos: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let store = MemoryStore()
        store.plans = [f.plan]
        let model = AppModel(store: store, engine: f.engine)

        model.startBackup()
        await model.waitForCurrentRun()

        let run = try #require(model.lastRun)
        #expect(run.outcome == .succeeded)
        #expect(run.protectedPhotos == 2)
        #expect(run.protectedFiles == 3)
    }
}
