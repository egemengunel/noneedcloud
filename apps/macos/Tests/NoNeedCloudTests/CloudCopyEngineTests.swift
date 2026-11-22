import Foundation
import Testing
@testable import NoNeedCloud

struct CloudCopyEngineTests {
    private func makeFile(_ relativePath: String, _ content: Data, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
    }

    private func mtime(_ relativePath: String, in root: URL) throws -> TimeInterval {
        try root.appendingPathComponent(relativePath).resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate!.timeIntervalSince1970
    }

    private func makeEngine(
        source: URL,
        destination: FakeBackupDestination,
        stateURL: URL
    ) -> CopyEngine {
        CopyEngine(
            sourceURL: source,
            destination: destination,
            destinationScope: "Docs",
            stateURL: stateURL
        )
    }

    @Test func healthCheckFailureFailsFastBeforeAnyCopy() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("a.txt", Data("a".utf8), in: source)
        try makeFile("b.txt", Data("b".utf8), in: source)

        let destination = FakeBackupDestination()
        destination.healthCheckError = DestinationError("S3 destination unreachable: cannot find host")
        let stateURL = root.appendingPathComponent("index.json")
        let engine = makeEngine(source: source, destination: destination, stateURL: stateURL)

        let result = await engine.run()

        #expect(result.outcome == .failed)
        #expect(result.itemsCopied == 0)
        #expect(result.itemsSkipped == 0)
        #expect(destination.copiedFiles.isEmpty)
        let errors = await engine.state.errors
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("S3 destination unreachable") == true)
        #expect(errors.first?.path == "Fake Destination")
    }

    @Test func engineScopesDestinationRelPathsWithDisplayName() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("nested/a.txt", Data("a".utf8), in: source)

        let destination = FakeBackupDestination()
        let engine = makeEngine(source: source, destination: destination, stateURL: root.appendingPathComponent("index.json"))

        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(destination.ensuredDirectories == ["Docs/nested"])
        #expect(destination.copiedFiles.map(\.relPath) == ["Docs/nested/a.txt"])
        #expect(destination.copiedFiles.first?.data == Data("a".utf8))
    }

    @Test func uploadFailureContinuesWithRemainingFiles() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("a.txt", Data("a".utf8), in: source)
        try makeFile("bad.txt", Data("bad".utf8), in: source)
        try makeFile("c.txt", Data("c".utf8), in: source)

        let destination = FakeBackupDestination()
        destination.copyErrors["Docs/bad.txt"] = DestinationError("S3 upload failed: HTTP 503")
        let stateURL = root.appendingPathComponent("index.json")
        let engine = makeEngine(source: source, destination: destination, stateURL: stateURL)

        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 2)
        #expect(result.itemsFailed == 1)
        #expect(destination.copiedFiles.map(\.relPath) == ["Docs/a.txt", "Docs/c.txt"])
        let errors = await engine.state.errors
        #expect(errors.first?.path == "bad.txt")
        #expect(errors.first?.reason.contains("503") == true)
    }

    @Test func failedUploadRemovesStaleIndexEntry() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("a.txt", Data("changed".utf8), in: source)

        let stateURL = root.appendingPathComponent("index.json")
        let staleIndex = IncrementalIndex(url: stateURL)
        staleIndex.update("a.txt", size: 3, mtime: 1_000)
        try staleIndex.save()

        let destination = FakeBackupDestination()
        destination.copyErrors["Docs/a.txt"] = DestinationError("upload refused")
        let engine = makeEngine(source: source, destination: destination, stateURL: stateURL)

        _ = await engine.run()

        let index = IncrementalIndex(url: stateURL)
        #expect(index.entry(for: "a.txt") == nil, "failed uploads must retry on the next run")
    }

    @Test func unchangedFilesSkipDestinationUploads() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("a.txt", Data("aaa".utf8), in: source)
        try makeFile("b.txt", Data("bbb".utf8), in: source)

        let stateURL = root.appendingPathComponent("index.json")
        let seed = IncrementalIndex(url: stateURL)
        seed.update("a.txt", size: 3, mtime: try mtime("a.txt", in: source))
        seed.update("b.txt", size: 3, mtime: try mtime("b.txt", in: source))
        try seed.save()

        let destination = FakeBackupDestination()
        let engine = makeEngine(source: source, destination: destination, stateURL: stateURL)

        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsSkipped == 2)
        #expect(result.itemsCopied == 0)
        #expect(destination.copiedFiles.isEmpty, "no server listing and no uploads for unchanged files")
    }

    @Test func indexPersistsAcrossRunsForCloudDestination() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeFile("a.txt", Data("aaa".utf8), in: source)

        let stateURL = root.appendingPathComponent("index.json")
        let destination = FakeBackupDestination()
        let first = makeEngine(source: source, destination: destination, stateURL: stateURL)
        _ = await first.run()

        let second = makeEngine(source: source, destination: destination, stateURL: stateURL)
        let secondResult = await second.run()

        #expect(secondResult.itemsSkipped == 1)
        #expect(secondResult.itemsCopied == 0)
    }
}

struct KeychainStoreTests {
    @Test func mockRoundTripSaveLoadDelete() throws {
        let keychain = MockKeychainStore()
        try #expect(keychain.load(account: "ref-1") == nil)
        try keychain.save(Data("s3cr3t".utf8), account: "ref-1")
        try #expect(keychain.load(account: "ref-1") == Data("s3cr3t".utf8))
        try keychain.save(Data("rotated".utf8), account: "ref-1")
        try #expect(keychain.load(account: "ref-1") == Data("rotated".utf8))
        try keychain.delete(account: "ref-1")
        try #expect(keychain.load(account: "ref-1") == nil)
    }

    @Test func s3SecretPayloadJSONRoundTrip() throws {
        let payload = S3SecretPayload(secretAccessKey: "s3cr3t", sessionToken: "tok")
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(S3SecretPayload.self, from: data)
        #expect(decoded.secretAccessKey == "s3cr3t")
        #expect(decoded.sessionToken == "tok")

        let minimal = try JSONDecoder().decode(S3SecretPayload.self, from: Data(#"{"secretAccessKey":"k"}"#.utf8))
        #expect(minimal.sessionToken == nil)
    }
}

@MainActor
struct AppModelCloudDestinationTests {
    @Test func photosToCloudDestinationFailsRunWithClearReason() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(store: store, runStateDirectory: root)
        let plan = TestSupport.makePlan(
            name: "Cloud Photos",
            sources: [],
            includePhotos: true,
            destination: .gdrive(CloudTokenConfig(secretRef: "gd-ref"))
        )

        let results = await model.backup(plan)

        #expect(results.count == 1)
        #expect(results[0].outcome == .failed)
        #expect(results[0].itemsFailed == 1)
        let record = try #require(model.history.last)
        #expect(record.outcome == .failed)
        #expect(record.errors.first?.path == "Photos")
        #expect(record.errors.first?.reason.contains("folder destination") == true)
    }
}
