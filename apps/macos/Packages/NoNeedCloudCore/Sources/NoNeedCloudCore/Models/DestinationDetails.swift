import Foundation

/// What we know about the volume a destination lives on. Refreshed by the
/// health check and saved with the plan, so the UI can still describe a
/// destination (and how to reconnect it) while it's unreachable.
public struct DestinationDetails: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The Mac's own disk.
        case internalDisk
        /// USB / Thunderbolt drive.
        case externalDisk
        /// NAS or server share.
        case network
    }

    public var volumeName: String
    public var kind: Kind
    /// e.g. "SMB", "AFP", "WebDAV" for network volumes.
    public var networkProtocol: String?
    /// e.g. "smb://home-archive.local/NoNeedCloud", for reconnecting in Finder.
    public var remountURL: String?
    public var freeBytes: Int64?
    public var isWritable: Bool

    public init(
        volumeName: String,
        kind: Kind,
        networkProtocol: String? = nil,
        remountURL: String? = nil,
        freeBytes: Int64? = nil,
        isWritable: Bool
    ) {
        self.volumeName = volumeName
        self.kind = kind
        self.networkProtocol = networkProtocol
        self.remountURL = remountURL
        self.freeBytes = freeBytes
        self.isWritable = isWritable
    }

    /// Reads volume information for a folder that is currently reachable.
    public static func inspect(_ url: URL) -> DestinationDetails? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeIsLocalKey, .volumeIsInternalKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            .volumeURLForRemountingKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        let remount = values.volumeURLForRemounting
        let kind: Kind
        if values.volumeIsLocal == false || remount != nil {
            kind = .network
        } else if values.volumeIsInternal == true {
            kind = .internalDisk
        } else {
            kind = .externalDisk
        }
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)

        return DestinationDetails(
            volumeName: values.volumeLocalizedName ?? url.lastPathComponent,
            kind: kind,
            networkProtocol: remount?.scheme?.uppercased(),
            remountURL: remount?.absoluteString,
            freeBytes: free,
            isWritable: FileManager.default.isWritableFile(atPath: url.path)
        )
    }
}
