import Foundation
import Testing
@testable import NoNeedCloud

struct MirroringEngineTests {
    private func makeFile(_ relativePath: String, _ content: Data, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
    }

    private func makeTree(_ files: [String: Data], in root: URL) throws {
        for (relativePath, content) in files {
            try makeFile(relativePath, content, in: root)
        }
    }

    private func makeEngine(
        source: URL,
        destination: URL,
        stateDirectory: URL,
        mirrorOptions: MirrorOptions = .disabled,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> CopyEngine {
        CopyEngine(
            sourceURL: source,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, source: source),
            mirrorOptions: mirrorOptions,
            now: now
        )
    }

    private func fileSubpaths(of root: URL) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { subpath in
            !(try root.appendingPathComponent(subpath).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        }
    }

    private func removedFolderName(daysBefore: Int, from date: Date) -> String {
        let previous = Calendar.current.date(byAdding: .day, value: -daysBefore, to: date)!
        return RetentionPolicy.folderName(for: previous)
    }

    @Test func mirroringMovesDeletedSourceFilesIntoDeletedDateFolder() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "gone.txt": Data("gone".utf8),
            "nested/gone-too.bin": Data("gone-too".utf8),
            "kept.txt": Data("kept".utf8),
        ], in: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let dateFolder = RetentionPolicy.folderName(for: nowDate)
        let mirrorOptions = MirrorOptions(enabled: true, retention: .days(90))

        let first = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 3)

        try FileManager.default.removeItem(at: source.appendingPathComponent("gone.txt"))
        try FileManager.default.removeItem(at: source.appendingPathComponent("nested/gone-too.bin"))

        let second = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let secondResult = await second.run()

        #expect(secondResult.outcome == .completed)
        #expect(secondResult.itemsMirrored == 2)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(dateFolder)/gone.txt")) == Data("gone".utf8))
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(dateFolder)/nested/gone-too.bin")) == Data("gone-too".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("gone.txt").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("nested/gone-too.bin").path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("kept.txt")) == Data("kept".utf8))

        let index = IncrementalIndex(url: IncrementalIndex.indexFileURL(stateDirectory: root, source: source))
        #expect(index.entry(for: "gone.txt") == nil)
        #expect(index.entry(for: "nested/gone-too.bin") == nil)
        #expect(index.entry(for: "kept.txt") != nil)

        let destinationFiles = Set(try fileSubpaths(of: destination))
        #expect(destinationFiles == Set([
            "kept.txt",
            "Deleted/\(dateFolder)/gone.txt",
            "Deleted/\(dateFolder)/nested/gone-too.bin",
        ]))
    }

    @Test func mirroringDisabledLeavesDestinationUntouchedAndReconcilesIndex() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "a.txt": Data("a".utf8),
            "b.txt": Data("b".utf8),
        ], in: source)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root)
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 2)
        let filesAfterFirstRun = Set(try fileSubpaths(of: destination))

        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))

        let second = makeEngine(source: source, destination: destination, stateDirectory: root)
        let secondResult = await second.run()

        #expect(secondResult.outcome == .completed)
        #expect(secondResult.itemsMirrored == 0)
        #expect(Set(try fileSubpaths(of: destination)) == filesAfterFirstRun)
        #expect(try Data(contentsOf: destination.appendingPathComponent("a.txt")) == Data("a".utf8))

        let index = IncrementalIndex(url: IncrementalIndex.indexFileURL(stateDirectory: root, source: source))
        #expect(index.entry(for: "a.txt") == nil)
        #expect(index.entry(for: "b.txt") != nil)
    }

    @Test func mirroringWithUnsupportedDestinationRecordsOneWarningAndMovesNothing() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeTree(["a.txt": Data("a".utf8)], in: source)
        let destination = FakeBackupDestination()
        let stateURL = IncrementalIndex.indexFileURL(stateDirectory: root, source: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let mirrorOptions = MirrorOptions(enabled: true, retention: .days(90))

        let first = CopyEngine(sourceURL: source, destination: destination, stateURL: stateURL, mirrorOptions: mirrorOptions, now: { nowDate })
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 1)

        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))

        let second = CopyEngine(sourceURL: source, destination: destination, stateURL: stateURL, mirrorOptions: mirrorOptions, now: { nowDate })
        let secondResult = await second.run()

        #expect(secondResult.outcome == .completed)
        #expect(secondResult.itemsMirrored == 0)
        #expect(destination.movedToDeleted.isEmpty)
        let errors = await second.state.errors
        #expect(errors.count == 1)
        #expect(errors.first?.path == destination.label)
        #expect(errors.first?.reason.contains("local folder destinations only") == true)

        let index = IncrementalIndex(url: stateURL)
        #expect(index.entry(for: "a.txt") == nil)
    }

    @Test func failedMirrorMoveKeepsIndexEntryForRetryOnNextRun() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try makeTree(["a.txt": Data("a".utf8)], in: source)
        let destination = FakeBackupDestination()
        destination.mirroringSupported = true
        destination.moveToDeletedError = DestinationError("Simulated move failure")
        let stateURL = IncrementalIndex.indexFileURL(stateDirectory: root, source: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let mirrorOptions = MirrorOptions(enabled: true, retention: .days(90))

        let first = CopyEngine(sourceURL: source, destination: destination, stateURL: stateURL, mirrorOptions: mirrorOptions, now: { nowDate })
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 1)

        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))

        let second = CopyEngine(sourceURL: source, destination: destination, stateURL: stateURL, mirrorOptions: mirrorOptions, now: { nowDate })
        let secondResult = await second.run()

        #expect(secondResult.itemsMirrored == 0)
        let errors = await second.state.errors
        #expect(errors.count == 1)
        #expect(errors.first?.path == "a.txt")
        let indexAfterFailure = IncrementalIndex(url: stateURL)
        #expect(indexAfterFailure.entry(for: "a.txt") != nil)

        destination.moveToDeletedError = nil
        let third = CopyEngine(sourceURL: source, destination: destination, stateURL: stateURL, mirrorOptions: mirrorOptions, now: { nowDate })
        let thirdResult = await third.run()

        #expect(thirdResult.itemsMirrored == 1)
        let indexAfterRetry = IncrementalIndex(url: stateURL)
        #expect(indexAfterRetry.entry(for: "a.txt") == nil)
    }

    @Test func untilNextBackupPurgesPreviousDateFoldersBeforeThisRunsMoves() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree(["a.txt": Data("a".utf8)], in: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let dateFolder = RetentionPolicy.folderName(for: nowDate)
        let previousFolder1 = removedFolderName(daysBefore: 3, from: nowDate)
        let previousFolder2 = removedFolderName(daysBefore: 10, from: nowDate)
        let mirrorOptions = MirrorOptions(enabled: true, retention: .untilNextBackup)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 1)

        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))
        try makeFile("\(previousFolder1)/old1.txt", Data("old1".utf8), in: destination.appendingPathComponent("Deleted"))
        try makeFile("\(previousFolder2)/old2.txt", Data("old2".utf8), in: destination.appendingPathComponent("Deleted"))

        let second = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let secondResult = await second.run()

        #expect(secondResult.itemsMirrored == 1)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Deleted/\(previousFolder1)").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Deleted/\(previousFolder2)").path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(dateFolder)/a.txt")) == Data("a".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
    }

    @Test func daysRetentionPurgesFoldersOlderThanWindow() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree(["a.txt": Data("a".utf8)], in: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let oldFolder = removedFolderName(daysBefore: 40, from: nowDate)
        let recentFolder = removedFolderName(daysBefore: 5, from: nowDate)
        let mirrorOptions = MirrorOptions(enabled: true, retention: .days(30))

        try makeFile("\(oldFolder)/old.txt", Data("old".utf8), in: destination.appendingPathComponent("Deleted"))
        try makeFile("\(recentFolder)/recent.txt", Data("recent".utf8), in: destination.appendingPathComponent("Deleted"))

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Deleted/\(oldFolder)").path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(recentFolder)/recent.txt")) == Data("recent".utf8))
    }

    @Test func foreverRetentionPurgesNothing() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree(["a.txt": Data("a".utf8)], in: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let ancientFolder = removedFolderName(daysBefore: 400, from: nowDate)
        let mirrorOptions = MirrorOptions(enabled: true, retention: .forever)

        try makeFile("\(ancientFolder)/ancient.txt", Data("ancient".utf8), in: destination.appendingPathComponent("Deleted"))

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(ancientFolder)/ancient.txt")) == Data("ancient".utf8))
    }

    @Test func deletingAgainOnSameDateReplacesEarlierDeletedCopy() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree(["a.txt": Data("v1".utf8)], in: source)
        let nowDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let dateFolder = RetentionPolicy.folderName(for: nowDate)
        let mirrorOptions = MirrorOptions(enabled: true, retention: .days(90))

        let first = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        _ = await first.run()
        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))
        let second = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let secondResult = await second.run()
        #expect(secondResult.itemsMirrored == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(dateFolder)/a.txt")) == Data("v1".utf8))

        try makeFile("a.txt", Data("v2".utf8), in: source)
        let third = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let thirdResult = await third.run()
        #expect(thirdResult.itemsCopied == 1)

        try FileManager.default.removeItem(at: source.appendingPathComponent("a.txt"))
        let fourth = makeEngine(source: source, destination: destination, stateDirectory: root, mirrorOptions: mirrorOptions, now: { nowDate })
        let fourthResult = await fourth.run()

        #expect(fourthResult.itemsMirrored == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Deleted/\(dateFolder)/a.txt")) == Data("v2".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
    }
}

struct RetentionPolicyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func folder(_ year: Int, _ month: Int, _ day: Int) -> String {
        RetentionPolicy.folderName(for: date(year, month, day), calendar: calendar)
    }

    @Test func daysRetentionPurgesFoldersOlderThanWindowAcrossMonthBoundary() {
        let purged = RetentionPolicy.foldersToPurge(
            folderNames: [folder(2025, 11, 30), folder(2025, 12, 1), folder(2026, 2, 28), "not-a-date"],
            runDate: date(2026, 3, 1),
            retention: .days(90),
            calendar: calendar
        )
        #expect(purged == [folder(2025, 11, 30)])
    }

    @Test func daysRetentionThirtyDayWindowKeepsBoundaryDay() {
        let purged = RetentionPolicy.foldersToPurge(
            folderNames: [folder(2026, 10, 22), folder(2026, 10, 23), folder(2026, 11, 22)],
            runDate: date(2026, 11, 22),
            retention: .days(30),
            calendar: calendar
        )
        #expect(purged == [folder(2026, 10, 22)])
    }

    @Test func daysRetentionIgnoresUnparseableFolderNames() {
        let purged = RetentionPolicy.foldersToPurge(
            folderNames: ["garbage", "2026-13-45", "2026-1-1", "20260101"],
            runDate: date(2026, 11, 22),
            retention: .days(30),
            calendar: calendar
        )
        #expect(purged.isEmpty)
    }

    @Test func foreverRetentionNeverPurges() {
        let purged = RetentionPolicy.foldersToPurge(
            folderNames: [folder(2000, 1, 1), folder(2026, 11, 22)],
            runDate: date(2026, 11, 22),
            retention: .forever,
            calendar: calendar
        )
        #expect(purged.isEmpty)
    }

    @Test func untilNextBackupPurgesAllFoldersExceptCurrentRunDate() {
        let purged = RetentionPolicy.foldersToPurge(
            folderNames: [folder(2026, 11, 21), folder(2026, 11, 22), folder(2020, 1, 1), "garbage"],
            runDate: date(2026, 11, 22),
            retention: .untilNextBackup,
            calendar: calendar
        )
        #expect(purged == [folder(2026, 11, 21), folder(2020, 1, 1), "garbage"])
    }

    @Test func emptyFolderListPurgesNothing() {
        for retention in [Retention.forever, .days(30), .untilNextBackup] {
            #expect(RetentionPolicy.foldersToPurge(folderNames: [], runDate: date(2026, 11, 22), retention: retention, calendar: calendar).isEmpty)
        }
    }
}

struct MirrorOptionsCodableTests {
    @Test func legacyPlanJSONWithoutMirrorOptionsDecodesToDisabled() throws {
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
        #expect(plans[0].mirrorOptions == .disabled)
        #expect(plans[0].mirrorOptions.enabled == false)
        #expect(plans[0].mirrorOptions.retention == .days(90))
    }

    @Test func mirrorOptionsRoundTripThroughPlanEncoding() throws {
        var plan = TestSupport.makePlan(name: "Mirror")
        plan.mirrorOptions = MirrorOptions(enabled: true, retention: .untilNextBackup)
        let data = try JSONEncoder().encode([plan])
        let decoded = try JSONDecoder().decode([BackupPlan].self, from: data)
        #expect(decoded[0].mirrorOptions == MirrorOptions(enabled: true, retention: .untilNextBackup))
    }

    @Test func partialMirrorOptionsJSONFillsRetentionDefault() throws {
        let options = try JSONDecoder().decode(MirrorOptions.self, from: Data(#"{"enabled": true}"#.utf8))
        #expect(options.enabled == true)
        #expect(options.retention == .days(90))
    }
}
