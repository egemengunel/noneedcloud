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
        let sanitized = source.lastPathComponent.map {
            $0.isLetter || $0.isNumber ? $0 : "-"
        }.reduce(into: "") { $0.append($1) }
        let digest = SHA256.hash(data: Data(source.path(percentEncoded: false).utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return stateDirectory
            .appendingPathComponent("RunState", isDirectory: true)
            .appendingPathComponent("index-\(sanitized)-\(fingerprint).json")
    }
}
