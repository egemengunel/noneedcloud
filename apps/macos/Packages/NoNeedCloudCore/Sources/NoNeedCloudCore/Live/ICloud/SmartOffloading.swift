import Foundation
import os

enum SmartOffloadOutcome: Sendable {
    case copied
    case fetchFailed(Error)
    case copyFailed(Error)
}

enum SmartOffload {
    static func run(
        for fileURL: URL,
        source: (any UbiquitousFileSource)?,
        isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
        copy: () async throws -> Void
    ) async -> SmartOffloadOutcome {
        guard let source, isDataless(fileURL, source: source) else {
            return await copyOnly(copy)
        }
        do {
            try await source.fetch(fileURL, isCancelled: isCancelled)
        } catch {
            await evict(fileURL, source: source)
            return .fetchFailed(error)
        }
        do {
            try await copy()
        } catch {
            await evict(fileURL, source: source)
            return .copyFailed(error)
        }
        await evict(fileURL, source: source)
        return .copied
    }

    private static func copyOnly(_ copy: () async throws -> Void) async -> SmartOffloadOutcome {
        do {
            try await copy()
            return .copied
        } catch {
            return .copyFailed(error)
        }
    }

    private static let logger = Logger(subsystem: "com.noneedcloud.mac", category: "SmartOffload")

    private static func evict(_ url: URL, source: any UbiquitousFileSource) async {
        do {
            try await source.evict(url)
        } catch {
            logger.error("Couldn't free \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private static func isDataless(_ url: URL, source: any UbiquitousFileSource) -> Bool {
        (try? source.isDataless(url)) ?? false
    }
}
