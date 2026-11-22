import AppKit
import NoNeedCloudCore

enum FolderPicker {
    /// Shows an open panel and returns bookmarked references to the chosen folders.
    @MainActor
    static func chooseFolders(
        message: String,
        prompt: String = "Choose",
        allowsMultiple: Bool = true
    ) -> [FolderReference] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        var folders: [FolderReference] = []
        for url in panel.urls {
            do {
                folders.append(try FolderReference(url: url))
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        return folders
    }

    @MainActor
    static func chooseDestination() -> FolderReference? {
        chooseFolders(
            message: "Choose a folder on a drive you own. NoNeedCloud keeps your backup inside it.",
            prompt: "Use as Destination",
            allowsMultiple: false
        ).first
    }
}
