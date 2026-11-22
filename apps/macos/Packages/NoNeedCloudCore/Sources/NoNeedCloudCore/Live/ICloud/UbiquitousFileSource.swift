import Foundation

protocol UbiquitousFileSource: AnyObject, Sendable {
    func isDataless(_ url: URL) throws -> Bool
    func fetch(_ url: URL, isCancelled: @escaping @Sendable () -> Bool) async throws
    func evict(_ url: URL) async throws
}

enum ICloudSourceError: LocalizedError {
    case downloadTimedOut(URL)

    var errorDescription: String? {
        switch self {
        case .downloadTimedOut(let url):
            return "Timed out downloading \(url.lastPathComponent) from iCloud."
        }
    }
}

final class ICloudDriveSource: UbiquitousFileSource {
    static var mobileDocumentsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)
    }

    static var cloudDocsRootURL: URL {
        mobileDocumentsRoot.appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
    }

    static func appContainerDocumentsURL(groupID: String, homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)
            .appendingPathComponent(groupID, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }

    private let downloadTimeout: TimeInterval
    private let pollIntervalNanos: UInt64

    init(downloadTimeout: TimeInterval = 60) {
        self.downloadTimeout = downloadTimeout
        self.pollIntervalNanos = 50_000_000
    }

    func isDataless(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values.ubiquitousItemDownloadingStatus else { return false }
        return status != .current
    }

    func fetch(_ url: URL, isCancelled: @escaping @Sendable () -> Bool) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(downloadTimeout)
        while Date() < deadline {
            if isCancelled() || Task.isCancelled { throw CancellationError() }
            if try !isDataless(url) { return }
            try await Task.sleep(nanoseconds: pollIntervalNanos)
        }
        throw ICloudSourceError.downloadTimedOut(url)
    }

    func evict(_ url: URL) async throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}
