import Foundation

public enum DestinationHealth {
    /// The destination folder resolves, exists and is a directory.
    /// Writability and free space checks come with destination preflight (M3).
    public static func isAvailable(_ destination: FolderReference) -> Bool {
        (try? destination.withAccess { url -> Bool in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }) ?? false
    }
}
