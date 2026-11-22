import Foundation
@testable import NoNeedCloud

final class MockKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var saveCount = 0

    func save(_ data: Data, account: String) throws {
        lock.withLock {
            items[account] = data
            saveCount += 1
        }
    }

    func load(account: String) -> Data? {
        lock.withLock { items[account] }
    }

    func delete(account: String) {
        lock.withLock { items[account] = nil }
    }
}

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [CloudHTTPRequest] = []
    private(set) var recordedBodies: [Data] = []
    var responder: @Sendable (CloudHTTPRequest) throws -> CloudHTTPResponse

    init(responder: @escaping @Sendable (CloudHTTPRequest) throws -> CloudHTTPResponse = { _ in
        CloudHTTPResponse(status: 200, data: Data())
    }) {
        self.responder = responder
    }

    func send(_ request: CloudHTTPRequest) async throws -> CloudHTTPResponse {
        lock.withLock { requests.append(request) }
        if let bodyFileURL = request.bodyFileURL, let body = try? Data(contentsOf: bodyFileURL) {
            lock.withLock { recordedBodies.append(body) }
        }
        return try responder(request)
    }
}

final class FakeBackupDestination: BackupDestination, @unchecked Sendable {
    let label = "Fake Destination"
    var healthCheckError: Error?
    var copyErrors: [String: Error] = [:]

    private let lock = NSLock()
    private(set) var ensuredDirectories: [String] = []
    private(set) var copiedFiles: [(relPath: String, sourceModificationDate: Date, data: Data)] = []

    func healthCheck() async throws {
        if let healthCheckError { throw healthCheckError }
    }

    func ensureDirectory(relPath: String) throws {
        lock.withLock { ensuredDirectories.append(relPath) }
    }

    func copyFile(relPath: String, fromFile: URL, sourceModificationDate: Date, isCancelled: @escaping @Sendable () -> Bool) throws {
        if let error = copyErrors[relPath] { throw error }
        let data = try Data(contentsOf: fromFile)
        lock.withLock { copiedFiles.append((relPath, sourceModificationDate, data)) }
    }

    func destinationFileExists(relPath: String) -> Bool { false }
}
