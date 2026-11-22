import Foundation
import Testing
@testable import NoNeedCloud

struct BackupSourceTests {
    @Test func sourceCatalogUsesGroupContainerIDs() {
        #expect(BackupSource.pages == .appContainer(groupID: "com~apple~Pages", displayName: "Pages"))
        #expect(BackupSource.numbers == .appContainer(groupID: "com~apple~Numbers", displayName: "Numbers"))
        #expect(BackupSource.icloudDrive.displayName == "iCloud Drive")
        #expect(BackupSource.pages.displayName == "Pages")
        #expect(BackupSource.numbers.displayName == "Numbers")
    }

    @Test func sourceNamesAndURLsResolve() {
        let folder = URL(fileURLWithPath: "/Users/test/Docs")
        #expect(BackupSource.folder(folder).displayName == "Docs")
        #expect(BackupSource.folder(folder).sourceURL == folder)

        let mobileRoot = ICloudDriveSource.mobileDocumentsRoot
        #expect(BackupSource.icloudDrive.sourceURL == mobileRoot.appendingPathComponent("com~apple~CloudDocs", isDirectory: true))
        #expect(BackupSource.pages.sourceURL == mobileRoot.appendingPathComponent("com~apple~Pages/Documents", isDirectory: true))
        #expect(BackupSource.numbers.sourceURL == mobileRoot.appendingPathComponent("com~apple~Numbers/Documents", isDirectory: true))
    }

    @Test func appContainerURLResolvesToDocumentsInGroupContainer() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let resolved = ICloudDriveSource.appContainerDocumentsURL(groupID: "com~apple~Pages", homeDirectory: home)
        #expect(resolved == home.appendingPathComponent("Library/Mobile Documents/com~apple~Pages/Documents", isDirectory: true))
    }

    @Test func backupSourceCodableRoundTrip() throws {
        let sources: [BackupSource] = [
            .folder(URL(fileURLWithPath: "/Users/test/Docs")),
            .icloudDrive,
            .appContainer(groupID: "com~apple~Pages", displayName: "Pages"),
        ]
        let data = try JSONEncoder().encode(sources)
        let decoded = try JSONDecoder().decode([BackupSource].self, from: data)
        #expect(decoded == sources)
    }

    @Test func planWithICloudSourcesRoundTripsThroughJSON() throws {
        let folder = URL(fileURLWithPath: "/Users/test/Docs")
        let plan = BackupPlan(
            name: "Cloud Plan",
            sources: [.icloudDrive, .pages, .numbers, .folder(folder)],
            includePhotos: false,
            photoOptions: PhotoOptions(),
            destinationURL: URL(fileURLWithPath: "/tmp/dest")
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BackupPlan.self, from: data)
        #expect(decoded == plan)
        #expect(decoded.sourceFolderURLs == [folder])
    }

    @Test func legacyPlansJSONDecodesIntoFolderSources() throws {
        let json = """
        [
          {
            "id": "F0E4C2FD-0C3B-4A46-9C13-3C1B1D6B9A11",
            "name": "Legacy Plan",
            "sourceFolderURLs": ["file:///Users/test/Docs"],
            "includePhotos": false,
            "photoOptions": {"fullTimeline": true},
            "destinationURL": "file:///tmp/dest",
            "schedule": "manual"
          }
        ]
        """
        let plans = try JSONDecoder().decode([BackupPlan].self, from: Data(json.utf8))
        #expect(plans.count == 1)
        #expect(plans[0].sources == [.folder(URL(fileURLWithPath: "/Users/test/Docs"))])
        #expect(plans[0].sourceFolderURLs == [URL(fileURLWithPath: "/Users/test/Docs")])
        #expect(plans[0].schedule == .manual)
    }

    @Test func legacyPlanPersistsAsNewFormatAfterResave() throws {
        let json = """
        [
          {
            "id": "F0E4C2FD-0C3B-4A46-9C13-3C1B1D6B9A11",
            "name": "Legacy Plan",
            "sourceFolderURLs": ["file:///Users/test/Docs"],
            "includePhotos": true,
            "photoOptions": {},
            "destinationURL": "file:///tmp/dest"
          }
        ]
        """
        let plan = try JSONDecoder().decode([BackupPlan].self, from: Data(json.utf8))[0]
        let reencoded = try JSONEncoder().encode([plan])
        let roundTripped = try JSONDecoder().decode([BackupPlan].self, from: reencoded)
        #expect(roundTripped == [plan])
        let raw = String(data: reencoded, encoding: .utf8) ?? ""
        #expect(raw.contains("\"sources\""))
        #expect(!raw.contains("sourceFolderURLs"))
    }

    @Test func eachSourceGetsItsOwnIndexFile() {
        let stateDirectory = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let docsA = URL(fileURLWithPath: "/root/A/Docs")
        let docsB = URL(fileURLWithPath: "/root/B/Docs")
        let sources: [BackupSource] = [.folder(docsA), .folder(docsB), .icloudDrive, .pages, .numbers]

        let urls = sources.map { IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, source: $0) }
        #expect(Set(urls).count == urls.count)
        #expect(IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, source: .folder(docsA))
            == IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, source: docsA))
    }

    @Test func sourcesDoNotCrossContaminateEachOthersIndex() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: first.appendingPathComponent("a.txt"))
        try Data("two".utf8).write(to: second.appendingPathComponent("a.txt"))

        func makeEngine(for source: URL) -> CopyEngine {
            CopyEngine(
                sourceURL: source,
                destinationURL: destination.appendingPathComponent(source.lastPathComponent, isDirectory: true),
                stateURL: IncrementalIndex.indexFileURL(
                    stateDirectory: root,
                    source: BackupSource.folder(source)
                )
            )
        }

        #expect(await makeEngine(for: first).run().itemsCopied == 1)
        #expect(await makeEngine(for: second).run().itemsCopied == 1)
        #expect(await makeEngine(for: first).run().itemsSkipped == 1)
        #expect(await makeEngine(for: second).run().itemsSkipped == 1)

        let firstIndex = IncrementalIndex(url: IncrementalIndex.indexFileURL(stateDirectory: root, source: BackupSource.folder(first)))
        let secondIndex = IncrementalIndex(url: IncrementalIndex.indexFileURL(stateDirectory: root, source: BackupSource.folder(second)))
        #expect(firstIndex.count == 1)
        #expect(secondIndex.count == 1)
    }
}
