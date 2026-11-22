import Foundation
import Testing
@testable import NoNeedCloud

struct CopyEngineTests {
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

    private func readData(_ relativePath: String, in root: URL) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    private func modificationDate(_ relativePath: String, in root: URL) throws -> Date {
        try root.appendingPathComponent(relativePath).resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate!
    }

    private func setModificationDate(_ date: Date, on path: String, in root: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: root.appendingPathComponent(path).path
        )
    }

    private func makeEngine(source: URL, destination: URL, stateDirectory: URL) -> CopyEngine {
        CopyEngine(
            sourceURL: source,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: stateDirectory, source: source)
        )
    }

    private func fileSubpaths(of root: URL) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { subpath in
            !(try root.appendingPathComponent(subpath).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        }
    }

    @Test func firstRunCopiesFullTreePreservingHierarchy() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let files: [String: Data] = [
            "root.txt": Data("root".utf8),
            "nested/a.txt": Data("a".utf8),
            "nested/deep/b.txt": Data("b".utf8),
            "other/c.txt": Data("c".utf8),
        ]
        try makeTree(files, in: source)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty-dir"), withIntermediateDirectories: true)

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root)
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 4)
        #expect(result.itemsSkipped == 0)
        for (relativePath, content) in files {
            #expect(try readData(relativePath, in: destination) == content)
        }
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("empty-dir").path))
        let sourceMtime = try modificationDate("nested/deep/b.txt", in: source)
        let destMtime = try modificationDate("nested/deep/b.txt", in: destination)
        #expect(abs(destMtime.timeIntervalSince(sourceMtime)) < 1)
    }

    @Test func secondRunCopiesOnlyChangedAndNewFiles() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "a.txt": Data("one".utf8),
            "d/b.txt": Data("two".utf8),
            "d/c.txt": Data("three".utf8),
        ], in: source)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root)
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 3)

        let untouchedMtimes = [
            "d/b.txt": try modificationDate("d/b.txt", in: destination),
            "d/c.txt": try modificationDate("d/c.txt", in: destination),
        ]

        let newTime = Date(timeIntervalSinceNow: 60)
        try Data("changed".utf8).write(to: source.appendingPathComponent("a.txt"))
        try setModificationDate(newTime, on: "a.txt", in: source)
        try makeFile("d/new.txt", Data("brand new".utf8), in: source)

        let second = makeEngine(source: source, destination: destination, stateDirectory: root)
        let secondResult = await second.run()

        #expect(secondResult.itemsCopied == 2)
        #expect(secondResult.itemsSkipped == 2)
        #expect(secondResult.itemsFailed == 0)
        #expect(try readData("a.txt", in: destination) == Data("changed".utf8))
        #expect(try readData("d/new.txt", in: destination) == Data("brand new".utf8))
        #expect(try modificationDate("d/b.txt", in: destination) == untouchedMtimes["d/b.txt"]!)
        #expect(try modificationDate("d/c.txt", in: destination) == untouchedMtimes["d/c.txt"]!)
        #expect(try modificationDate("a.txt", in: destination) == newTime)
    }

    @Test func statePersistsAcrossEngineInstances() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "x.txt": Data("x".utf8),
            "y.txt": Data("y".utf8),
        ], in: source)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root)
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 2)
        #expect(firstResult.itemsProtected == 2)

        let restarted = makeEngine(source: source, destination: destination, stateDirectory: root)
        let secondResult = await restarted.run()
        #expect(secondResult.outcome == .completed)
        #expect(secondResult.itemsCopied == 0)
        #expect(secondResult.itemsSkipped == 2)
        #expect(secondResult.itemsProtected == 2)
    }

    @Test func cancelMidRunStopsSafelyAndLeavesNoPartialFiles() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let chunk = Data(repeating: 0x41, count: 64 * 1024)
        var files: [String: Data] = [:]
        for index in 0..<50 {
            files["batch/file-\(index).bin"] = chunk
        }
        try makeTree(files, in: source)

        let engine = CopyEngine(
            sourceURL: source,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: root, source: source),
            perFileDelayNanos: 20_000_000
        )

        let task = Task { await engine.run() }
        let deadline = Date().addingTimeInterval(15)
        while await engine.state.itemsCopied < 3 && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        engine.stop()
        let result = await task.value

        #expect(result.outcome == .cancelled)
        #expect(await !engine.state.isRunning)
        let destinationFiles = try fileSubpaths(of: destination)
        for relativePath in destinationFiles {
            #expect(try readData(relativePath, in: destination) == chunk)
        }
        #expect(result.itemsCopied + result.itemsFailed == destinationFiles.count)
    }

    @Test func sourceTreeIsUnchangedAfterRuns() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "a.txt": Data("alpha".utf8),
            "nested/b.txt": Data("beta".utf8),
        ], in: source)

        func snapshot() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for subpath in try fileSubpaths(of: source) {
                result[subpath] = try Data(contentsOf: source.appendingPathComponent(subpath))
            }
            return result
        }

        let before = try snapshot()
        let beforeMtimes = [
            "a.txt": try modificationDate("a.txt", in: source),
            "nested/b.txt": try modificationDate("nested/b.txt", in: source),
        ]

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root)
        _ = await engine.run()
        let second = makeEngine(source: source, destination: destination, stateDirectory: root)
        _ = await second.run()

        #expect(try snapshot() == before)
        #expect(try modificationDate("a.txt", in: source) == beforeMtimes["a.txt"]!)
        #expect(try modificationDate("nested/b.txt", in: source) == beforeMtimes["nested/b.txt"]!)
    }

    @Test func unreadableFileIsSkippedAndRecordedWhileRunContinues() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "ok-before.txt": Data("before".utf8),
            "locked.txt": Data("secret".utf8),
            "ok-after.txt": Data("after".utf8),
        ], in: source)
        let lockedPath = source.appendingPathComponent("locked.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath.path) }

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root)
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 2)
        #expect(result.itemsFailed == 1)
        let errors = await engine.state.errors
        #expect(errors.count == 1)
        #expect(errors.first?.path == "locked.txt")
        #expect(try readData("ok-before.txt", in: destination) == Data("before".utf8))
        #expect(try readData("ok-after.txt", in: destination) == Data("after".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("locked.txt").path))
    }

    @Test func failedReCopyOfChangedFilePreservesPreviousVersionAndIndex() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeFile("important.txt", Data("one".utf8), in: source)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root)
        let firstResult = await first.run()
        #expect(firstResult.itemsCopied == 1)

        let newTime = Date(timeIntervalSinceNow: 60)
        try Data("changed-content".utf8).write(to: source.appendingPathComponent("important.txt"))
        try setModificationDate(newTime, on: "important.txt", in: source)

        let temporaryPath = destination.appendingPathComponent("important.txt.tmp").path
        try FileManager.default.createDirectory(atPath: temporaryPath, withIntermediateDirectories: true)

        let second = makeEngine(source: source, destination: destination, stateDirectory: root)
        let secondResult = await second.run()

        #expect(secondResult.outcome == .completed)
        #expect(secondResult.itemsCopied == 0)
        #expect(secondResult.itemsFailed == 1)
        #expect(try readData("important.txt", in: destination) == Data("one".utf8))
        #expect(!FileManager.default.fileExists(atPath: temporaryPath))
        let errors = await second.state.errors
        #expect(errors.first?.path == "important.txt")

        let index = IncrementalIndex(url: IncrementalIndex.indexFileURL(stateDirectory: root, source: source))
        #expect(index.entry(for: "important.txt")?.size == Int64("one".utf8.count))

        let third = makeEngine(source: source, destination: destination, stateDirectory: root)
        let thirdResult = await third.run()
        #expect(thirdResult.itemsCopied == 1)
        #expect(thirdResult.itemsSkipped == 0)
        #expect(try readData("important.txt", in: destination) == Data("changed-content".utf8))
    }

    @Test func missingSourceDirectoryFailsRunInsteadOfReportingSuccess() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Missing", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)

        let engine = makeEngine(source: source, destination: destination, stateDirectory: root)
        let result = await engine.run()

        #expect(result.outcome != .completed)
        #expect(result.itemsFailed > 0)
        #expect(result.itemsCopied == 0)
        #expect(await !engine.state.isRunning)
        let errors = await engine.state.errors
        #expect(errors.count == 1)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func incrementalPassReportsProgressForSkippedBytes() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try makeTree([
            "a.txt": Data("alpha".utf8),
            "b.txt": Data("beta".utf8),
        ], in: source)

        let first = makeEngine(source: source, destination: destination, stateDirectory: root)
        _ = await first.run()

        let second = makeEngine(source: source, destination: destination, stateDirectory: root)
        let secondResult = await second.run()
        #expect(secondResult.itemsSkipped == 2)
        let percent = await second.state.percent
        #expect(percent > 0.99)
    }

    @Test func cancelledRunPersistsProgressForNextRun() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let chunk = Data(repeating: 0x42, count: 64 * 1024)
        var files: [String: Data] = [:]
        for index in 0..<30 {
            files["b/file-\(index).bin"] = chunk
        }
        try makeTree(files, in: source)

        let engine = CopyEngine(
            sourceURL: source,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: root, source: source),
            perFileDelayNanos: 20_000_000
        )
        let task = Task { await engine.run() }
        let deadline = Date().addingTimeInterval(15)
        while await engine.state.itemsCopied < 3 && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        engine.stop()
        let cancelledResult = await task.value
        #expect(cancelledResult.outcome == .cancelled)

        let resumed = makeEngine(source: source, destination: destination, stateDirectory: root)
        let resumedResult = await resumed.run()
        #expect(resumedResult.outcome == .completed)
        #expect(resumedResult.itemsCopied == 30 - cancelledResult.itemsCopied)
        #expect(resumedResult.itemsSkipped == cancelledResult.itemsCopied)
    }
}

struct IncrementalIndexTests {
    @Test func indexPersistsEntriesAcrossStoreInstances() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("index.json")

        let writer = IncrementalIndex(url: url)
        writer.update("a/b.txt", size: 12, mtime: 1.5)
        writer.update("c.txt", size: 5, mtime: 2.5)
        try writer.save()

        let reader = IncrementalIndex(url: url)
        let entry = reader.entry(for: "a/b.txt")
        #expect(entry?.size == 12)
        #expect(entry?.mtime == 1.5)
        #expect(reader.entry(for: "c.txt") != nil)
        #expect(reader.entry(for: "missing") == nil)
        #expect(reader.count == 2)
    }

    @Test func missingIndexFileLoadsAsEmpty() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let index = IncrementalIndex(url: dir.appendingPathComponent("absent.json"))
        #expect(index.count == 0)
    }

    @Test func corruptIndexFileLoadsAsEmpty() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("index.json")
        try Data("garbage".utf8).write(to: url)
        let index = IncrementalIndex(url: url)
        #expect(index.count == 0)
    }
}
