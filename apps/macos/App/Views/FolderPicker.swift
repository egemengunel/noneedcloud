import AppKit
import NoNeedCloudCore

enum FolderPicker {
    /// Shows an open panel and returns a bookmarked reference to the chosen folder.
    @MainActor
    static func chooseFolder() -> FolderReference? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try FolderReference(url: url)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}
