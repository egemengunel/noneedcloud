import CryptoKit
import Foundation

struct IncrementalEntry: Codable, Equatable, Sendable {
    var size: Int64
    var mtime: TimeInterval
}

final class IncrementalIndex: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var entries: [String: IncrementalEntry] = [:]

    init(url: URL) {
        self.url = url
        load()
    }

    var count: Int {
        lock.withLock { entries.count }
    }

    func entry(for relativePath: String) -> IncrementalEntry? {
        lock.withLock { entries[relativePath] }
    }

    func update(_ relativePath: String, size: Int64, mtime: TimeInterval) {
        lock.withLock { entries[relativePath] = IncrementalEntry(size: size, mtime: mtime) }
    }

    func remove(_ relativePath: String) {
        _ = lock.withLock { entries.removeValue(forKey: relativePath) }
    }

    func save() throws {
        let data: Data
        let current: [String: IncrementalEntry] = lock.withLock { entries }
        data = try JSONEncoder().encode(current)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: IncrementalEntry].self, from: data)
        else { return }
        lock.withLock { entries = decoded }
    }

    static func indexFileURL(stateDirectory: URL, source: URL) -> URL {
        indexFileURL(
            stateDirectory: stateDirectory,
            sourceKey: source.path(percentEncoded: false),
            name: source.lastPathComponent
        )
    }

    static func indexFileURL(stateDirectory: URL, source: BackupSource) -> URL {
        indexFileURL(
            stateDirectory: stateDirectory,
            sourceKey: sourceKey(for: source),
            name: source.displayName
        )
    }

    /// The index records what has already been copied, so it must be scoped to
    /// the (source, destination) pair: two plans sharing a source but writing
    /// to different destinations each keep their own incremental state.
    static func indexFileURL(stateDirectory: URL, destination: URL, source: BackupSource) -> URL {
        indexFileURL(
            stateDirectory: stateDirectory,
            sourceKey: destination.path(percentEncoded: false) + "\n" + sourceKey(for: source),
            name: destination.lastPathComponent + "-" + source.displayName
        )
    }

    private static func sourceKey(for source: BackupSource) -> String {
        switch source {
        case .folder(let url):
            url.path(percentEncoded: false)
        case .icloudDrive:
            "icloud-drive"
        case .appContainer(let groupID, _):
            groupID
        }
    }

    private static func indexFileURL(stateDirectory: URL, sourceKey: String, name: String) -> URL {
        let sanitized = name.map {
            $0.isLetter || $0.isNumber ? $0 : "-"
        }.reduce(into: "") { $0.append($1) }
        let digest = SHA256.hash(data: Data(sourceKey.utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return stateDirectory
            .appendingPathComponent("index-\(sanitized)-\(fingerprint).json")
    }
}
