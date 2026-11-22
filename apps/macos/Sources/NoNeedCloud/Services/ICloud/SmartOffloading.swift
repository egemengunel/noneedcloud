import Foundation

enum SmartOffloadOutcome: Sendable {
    case copied
    case fetchFailed(Error)
    case copyFailed(Error)
}

enum SmartOffload {
    static func run(
        for fileURL: URL,
        source: (any UbiquitousFileSource)?,
        copy: () async throws -> Void
    ) async -> SmartOffloadOutcome {
        guard let source, isDataless(fileURL, source: source) else {
            return await copyOnly(copy)
        }
        do {
            try await source.fetch(fileURL)
        } catch {
            return .fetchFailed(error)
        }
        do {
            try await copy()
        } catch {
            try? await source.evict(fileURL)
            return .copyFailed(error)
        }
        try? await source.evict(fileURL)
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

    private static func isDataless(_ url: URL, source: any UbiquitousFileSource) -> Bool {
        (try? source.isDataless(url)) ?? false
    }
}
