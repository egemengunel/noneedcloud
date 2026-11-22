import Foundation
import Testing
@testable import NoNeedCloudCore

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ event: String) {
        lock.withLock { items.append(event) }
    }

    var events: [String] {
        lock.withLock { items }
    }
}

final class MockUbiquitousSource: UbiquitousFileSource, @unchecked Sendable {
    struct FetchFailed: Error {}

    let log: EventLog
    var datalessPaths: Set<String>
    var fetchError: Error?
    var fetchStallsUntilCancelled: Bool
    var materialize: (URL) -> Void

    init(
        log: EventLog = EventLog(),
        datalessPaths: Set<String> = [],
        fetchError: Error? = nil,
        fetchStallsUntilCancelled: Bool = false,
        materialize: @escaping (URL) -> Void = { _ in }
    ) {
        self.log = log
        self.datalessPaths = datalessPaths
        self.fetchError = fetchError
        self.fetchStallsUntilCancelled = fetchStallsUntilCancelled
        self.materialize = materialize
    }

    func isDataless(_ url: URL) throws -> Bool {
        datalessPaths.contains(url.path)
    }

    func fetch(_ url: URL, isCancelled: @escaping () -> Bool) async throws {
        log.append("fetch:\(url.lastPathComponent)")
        if fetchStallsUntilCancelled {
            while !isCancelled() {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw CancellationError()
        }
        if let fetchError { throw fetchError }
        materialize(url)
    }

    func evict(_ url: URL) async throws {
        log.append("evict:\(url.lastPathComponent)")
    }
}

struct SmartOffloadingTests {
    private func assertCopied(_ outcome: SmartOffloadOutcome) throws {
        guard case .copied = outcome else {
            Issue.record("Expected .copied, got \(outcome)")
            return
        }
    }

    @Test func datalessFileIsFetchedBeforeCopyAndEvictedAfterSuccess() async throws {
        let log = EventLog()
        let fileURL = URL(fileURLWithPath: "/icloud/file.txt")
        let source = MockUbiquitousSource(log: log, datalessPaths: [fileURL.path])

        let outcome = await SmartOffload.run(for: fileURL, source: source) {
            log.append("copy:file.txt")
        }

        try assertCopied(outcome)
        #expect(log.events == ["fetch:file.txt", "copy:file.txt", "evict:file.txt"])
    }

    @Test func materializedFileIsCopiedWithoutFetchOrEvict() async throws {
        let log = EventLog()
        let fileURL = URL(fileURLWithPath: "/icloud/file.txt")
        let source = MockUbiquitousSource(log: log)

        let outcome = await SmartOffload.run(for: fileURL, source: source) {
            log.append("copy:file.txt")
        }

        try assertCopied(outcome)
        #expect(log.events == ["copy:file.txt"])
    }

    @Test func fetchFailureRecordsOutcomeSkipsCopyAndEvicts() async throws {
        let log = EventLog()
        let fileURL = URL(fileURLWithPath: "/icloud/file.txt")
        let source = MockUbiquitousSource(log: log, datalessPaths: [fileURL.path], fetchError: MockUbiquitousSource.FetchFailed())

        let outcome = await SmartOffload.run(for: fileURL, source: source) {
            log.append("copy:file.txt")
        }

        guard case .fetchFailed = outcome else {
            Issue.record("Expected .fetchFailed, got \(outcome)")
            return
        }
        #expect(log.events == ["fetch:file.txt", "evict:file.txt"])
    }

    @Test func copyFailureAfterFetchStillEvicts() async throws {
        let log = EventLog()
        let fileURL = URL(fileURLWithPath: "/icloud/file.txt")
        let source = MockUbiquitousSource(log: log, datalessPaths: [fileURL.path])

        let outcome = await SmartOffload.run(for: fileURL, source: source) {
            log.append("copy:file.txt")
            throw CopyEngineFailure()
        }

        guard case .copyFailed = outcome else {
            Issue.record("Expected .copyFailed, got \(outcome)")
            return
        }
        #expect(log.events == ["fetch:file.txt", "copy:file.txt", "evict:file.txt"])
    }

    @Test func nilSourceCopiesWithoutUbiquitousHandling() async throws {
        let log = EventLog()
        let fileURL = URL(fileURLWithPath: "/plain/file.txt")

        let outcome = await SmartOffload.run(for: fileURL, source: nil) {
            log.append("copy:file.txt")
        }

        try assertCopied(outcome)
        #expect(log.events == ["copy:file.txt"])
    }

    @Test @MainActor func engineFetchesCopiesAndEvictsDatalessFile() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("plain".utf8).write(to: sourceDir.appendingPathComponent("ok.txt"))
        let placeholder = sourceDir.appendingPathComponent("placeholder.txt")
        try Data().write(to: placeholder)

        let log = EventLog()
        let datalessPath = placeholder.path
        let source = MockUbiquitousSource(log: log, datalessPaths: [datalessPath]) { url in
            try? Data("from icloud".utf8).write(to: url)
        }

        let engine = CopyEngine(
            sourceURL: sourceDir,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: root, source: sourceDir),
            ubiquitousSource: source
        )
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 2)
        #expect(try Data(contentsOf: destination.appendingPathComponent("ok.txt")) == Data("plain".utf8))
        #expect(try Data(contentsOf: destination.appendingPathComponent("placeholder.txt")) == Data("from icloud".utf8))
        #expect(log.events == ["fetch:placeholder.txt", "evict:placeholder.txt"])
    }

    @Test @MainActor func stopDuringStalledFetchReturnsCancelledWithinTwoSeconds() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data().write(to: sourceDir.appendingPathComponent("stuck.txt"))

        let source = MockUbiquitousSource(
            datalessPaths: [sourceDir.appendingPathComponent("stuck.txt").path],
            fetchStallsUntilCancelled: true
        )
        let engine = CopyEngine(
            sourceURL: sourceDir,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: root, source: sourceDir),
            ubiquitousSource: source
        )

        let runTask = Task(priority: .userInitiated) { await engine.run() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let stopAt = Date()
        engine.stop()
        let result = await runTask.value

        #expect(Date().timeIntervalSince(stopAt) < 2)
        #expect(result.outcome == .cancelled)
        #expect(result.itemsFailed == 0)
        #expect(engine.state.errors.isEmpty)
    }

    @Test @MainActor func fetchFailureRecordsErrorAndEngineContinues() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDir = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data().write(to: sourceDir.appendingPathComponent("bad.txt"))
        try Data("fine".utf8).write(to: sourceDir.appendingPathComponent("good.txt"))

        let log = EventLog()
        let source = MockUbiquitousSource(
            log: log,
            datalessPaths: [sourceDir.appendingPathComponent("bad.txt").path],
            fetchError: MockUbiquitousSource.FetchFailed()
        )

        let engine = CopyEngine(
            sourceURL: sourceDir,
            destinationURL: destination,
            stateURL: IncrementalIndex.indexFileURL(stateDirectory: root, source: sourceDir),
            ubiquitousSource: source
        )
        let result = await engine.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 1)
        #expect(result.itemsFailed == 1)
        #expect(engine.state.errors.count == 1)
        #expect(engine.state.errors[0].path == "bad.txt")
        #expect(!engine.state.errors[0].reason.isEmpty)
        #expect(try Data(contentsOf: destination.appendingPathComponent("good.txt")) == Data("fine".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("bad.txt").path))
        #expect(log.events == ["fetch:bad.txt", "evict:bad.txt"])
    }
}

private struct CopyEngineFailure: Error {}
