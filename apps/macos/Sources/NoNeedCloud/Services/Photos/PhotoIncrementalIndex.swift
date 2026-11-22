import CryptoKit
import Foundation

struct PhotoComponentFingerprint: Codable, Equatable, Sendable {
    var kind: String
    var filename: String
    var byteSize: Int64?
}

struct PhotoIndexEntry: Codable, Equatable, Sendable {
    var modificationDate: TimeInterval
    var fingerprints: [PhotoComponentFingerprint]
    var paths: [String: String]
}

final class PhotoIncrementalIndex: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var entries: [String: PhotoIndexEntry] = [:]

    init(url: URL) {
        self.url = url
        load()
    }

    var count: Int {
        lock.withLock { entries.count }
    }

    func entry(for identifier: String) -> PhotoIndexEntry? {
        lock.withLock { entries[identifier] }
    }

    func update(_ identifier: String, entry: PhotoIndexEntry) {
        lock.withLock { entries[identifier] = entry }
    }

    func save() throws {
        let data = try JSONEncoder().encode(lock.withLock { entries })
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: PhotoIndexEntry].self, from: data)
        else { return }
        lock.withLock { entries = decoded }
    }

    static func indexFileURL(stateDirectory: URL, destination: URL) -> URL {
        let sanitized = destination.lastPathComponent.map {
            $0.isLetter || $0.isNumber ? $0 : "-"
        }.reduce(into: "") { $0.append($1) }
        let digest = SHA256.hash(data: Data(destination.path(percentEncoded: false).utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return stateDirectory
            .appendingPathComponent("RunState", isDirectory: true)
            .appendingPathComponent("photo-index-\(sanitized)-\(fingerprint).json")
    }
}
