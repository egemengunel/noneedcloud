import NoNeedCloudCore
import SwiftUI

struct SourceFoldersSheet: View {
    let model: AppModel
    @State private var selection: Set<String> = []

    var body: some View {
        SheetChrome(
            title: "Source folders",
            subtitle: "Folders to back up, such as iCloud Drive, Desktop & Documents, or an app's iCloud folder."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Back up these folders", isOn: model.planBinding(\.files.isEnabled))
                    .disabled(model.plan.files.folders.isEmpty)

                List(selection: $selection) {
                    if model.plan.files.folders.isEmpty {
                        Text("No folders yet. Add iCloud Drive or any folder you want to protect.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.plan.files.folders, id: \.displayPath) { folder in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: folder))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName)
                                Text(folder.displayPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        .tag(folder.displayPath)
                        .contextMenu {
                            Button("Remove", role: .destructive) { model.removeFolder(folder) }
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 180)
                .onDeleteCommand(perform: removeSelected)

                HStack(spacing: 6) {
                    Button("Add Folder…", systemImage: "plus") {
                        let folders = FolderPicker.chooseFolders(message: "Choose folders to protect.", prompt: "Add")
                        model.addFolders(folders)
                    }
                    Button("Remove", systemImage: "minus", action: removeSelected)
                        .disabled(selection.isEmpty)
                }
                .labelStyle(.iconOnly)
            }
        } secondary: {
            Button("Remove All", role: .destructive) { model.removeAllFolders() }
                .disabled(model.plan.files.folders.isEmpty)
        }
        .frame(height: 480)
    }

    private func removeSelected() {
        for folder in model.plan.files.folders where selection.contains(folder.displayPath) {
            model.removeFolder(folder)
        }
        selection.removeAll()
    }

    private func icon(for folder: FolderReference) -> String {
        folder.displayPath.contains("Mobile Documents") ? "icloud" : "folder"
    }
}
