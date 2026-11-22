import Foundation

protocol UbiquitousFileSource: AnyObject, Sendable {
    func enumerateFiles(under root: URL) throws -> [URL]
    func isDataless(_ url: URL) throws -> Bool
    func fetch(_ url: URL) async throws
    func evict(_ url: URL) async throws
}

enum ICloudSourceError: LocalizedError {
    case enumerationFailed(URL)
    case downloadTimedOut(URL)

    var errorDescription: String? {
        switch self {
        case .enumerationFailed(let url):
            return "Could not enumerate iCloud folder at \(url.path)."
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

    static func containerURL(bundleID: String) -> URL {
        mobileDocumentsRoot.appendingPathComponent(bundleID, isDirectory: true)
    }

    private let downloadTimeout: TimeInterval
    private let pollIntervalNanos: UInt64

    init(downloadTimeout: TimeInterval = 60) {
        self.downloadTimeout = downloadTimeout
        self.pollIntervalNanos = 100_000_000
    }

    func enumerateFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            throw ICloudSourceError.enumerationFailed(root)
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == false {
                files.append(url)
            }
        }
        return files
    }

    func isDataless(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values.ubiquitousItemDownloadingStatus else { return false }
        return status != .current
    }

    func fetch(_ url: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(downloadTimeout)
        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            if try !isDataless(url) { return }
            try await Task.sleep(nanoseconds: pollIntervalNanos)
        }
        throw ICloudSourceError.downloadTimedOut(url)
    }

    func evict(_ url: URL) async throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}
