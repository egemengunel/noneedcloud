import NoNeedCloudCore
import SwiftUI

struct DestinationSheet: View {
    let model: AppModel

    var body: some View {
        SheetChrome(
            title: "Destination",
            subtitle: "Where your backup is kept. It's stored as plain files and folders you can open in Finder."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let destination = model.plan.destination {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination.displayName).font(.headline)
                            Text(destination.displayPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            if !model.health.destinationAvailable {
                                Label("Not connected", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("No destination yet.")
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button("Folder on a Drive or NAS…", systemImage: "externaldrive") { choose() }
                    Divider()
                    Section("Coming later") {
                        Button("Amazon S3 or Compatible…") {}.disabled(true)
                        Button("Google Drive…") {}.disabled(true)
                        Button("OneDrive…") {}.disabled(true)
                    }
                } label: {
                    Label(model.plan.destination == nil ? "Add Destination" : "Change Destination", systemImage: "plus")
                }
                .fixedSize()

                Text("Tip: drives formatted as APFS or exFAT work best. FAT32 drives can't store files larger than 4 GB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } secondary: {
            Button("Remove", role: .destructive) { model.setDestination(nil) }
                .disabled(model.plan.destination == nil)
        }
    }

    private func choose() {
        if let destination = FolderPicker.chooseDestination() {
            model.setDestination(destination)
        }
    }
}
