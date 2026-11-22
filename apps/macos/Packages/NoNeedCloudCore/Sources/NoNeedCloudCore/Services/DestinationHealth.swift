import Foundation

public enum DestinationHealth {
    /// The destination folder resolves, exists and is a directory.
    public static func isAvailable(_ destination: FolderReference) -> Bool {
        inspect(destination) != nil
    }

    /// Volume details for the destination, or nil if it can't be reached.
    public static func inspect(_ destination: FolderReference) -> DestinationDetails? {
        try? destination.withAccess { url -> DestinationDetails? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return DestinationDetails.inspect(url)
        } ?? nil
    }
}
