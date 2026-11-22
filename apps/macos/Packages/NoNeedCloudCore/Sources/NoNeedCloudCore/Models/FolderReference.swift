import Foundation

/// A folder the user picked, stored as a security-scoped bookmark so the
/// sandboxed app can reopen it after relaunch.
///
/// `displayPath` is only for showing in the UI. Always go through `resolve()`
/// or `withAccess(_:)` to touch the folder on disk.
public struct FolderReference: Codable, Hashable, Sendable {
    public var bookmark: Data
    public var displayPath: String

    public init(bookmark: Data, displayPath: String) {
        self.bookmark = bookmark
        self.displayPath = displayPath
    }

    /// Creates a reference from a URL the user just picked (e.g. from `NSOpenPanel`).
    public init(url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        self.init(bookmark: bookmark, displayPath: url.path(percentEncoded: false))
    }

    public var displayName: String {
        URL(fileURLWithPath: displayPath).lastPathComponent
    }

    public struct Resolved: Sendable {
        public var url: URL
        /// Set when the bookmark resolved but was stale; save this in place of the old one.
        public var refreshedReference: FolderReference?
    }

    public func resolve() throws -> Resolved {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let refreshed = isStale ? try? Self.refreshing(url) : nil
        return Resolved(url: url, refreshedReference: refreshed)
    }

    /// Resolves the bookmark and runs `body` while the security scope is open.
    public func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolve().url
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    private static func refreshing(_ url: URL) throws -> FolderReference {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try FolderReference(url: url)
    }
}
