import Foundation
import Testing
@testable import NoNeedCloudCore

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

    @Test func indexFileURLsDifferPerDestinationForSameSource() {
        let stateDirectory = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let source = BackupSource.folder(URL(fileURLWithPath: "/root/Docs"))
        let destinationA = URL(fileURLWithPath: "/volumes/A")
        let destinationB = URL(fileURLWithPath: "/volumes/B")

        #expect(IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destinationA, source: source)
            != IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destinationB, source: source))
        #expect(IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destinationA, source: source)
            == IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destinationA, source: source))
    }
}
