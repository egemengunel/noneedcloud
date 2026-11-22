import SwiftUI
import NoNeedCloudCore

struct SetupWizardView: View {
    @State private var flow = SetupFlow()
    let onFinish: (BackupPlan) -> Void

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            wizardFooter
        }
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(flow.step.rawValue) of 3")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(flow.step.title)
                .font(.title2)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .sources: SourcesStep(flow: flow)
        case .destination: DestinationStep(flow: flow)
        case .startBackup: StartBackupStep(flow: flow, onFinish: onFinish)
        }
    }

    private var wizardFooter: some View {
        HStack {
            if flow.step.previous != nil {
                Button("Back") { flow.back() }
            }
            Spacer()
            if flow.step.next != nil {
                Button("Continue") { flow.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!flow.canContinue)
            }
        }
        .padding(20)
    }
}

extension SetupFlow.Step {
    var title: String {
        switch self {
        case .sources: "What to protect"
        case .destination: "Where to keep your data"
        case .startBackup: "Start your first backup"
        }
    }
}

struct SourcesStep: View {
    @Bindable var flow: SetupFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the folders you want to protect.")
                .foregroundStyle(.secondary)

            Toggle("Include iCloud Photos", isOn: $flow.includePhotos)

            if flow.includePhotos {
                Text("Photos copying is a placeholder in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Folders")
                    .font(.headline)
                Spacer()
                Button("Add Folder…") { addFolder() }
            }

            if flow.sourceFolders.isEmpty {
                Text("No folders selected yet.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(flow.sourceFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.displayName)
                            Spacer()
                            Button {
                                flow.removeSourceFolder(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }

    private func addFolder() {
        if let folder = FolderPicker.chooseFolder() {
            flow.addSourceFolder(folder)
        }
    }
}

struct DestinationStep: View {
    @Bindable var flow: SetupFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a folder on a drive you own. It should stay connected during backups.")
                .foregroundStyle(.secondary)

            Button("Choose Folder…") { chooseDestination() }

            if let destination = flow.destination {
                Text(destination.displayPath)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
    }

    private func chooseDestination() {
        if let folder = FolderPicker.chooseFolder() {
            flow.destination = folder
        }
    }
}

struct StartBackupStep: View {
    @Bindable var flow: SetupFlow
    let onFinish: (BackupPlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Sources") { Text(sourcesSummary) }
                LabeledContent("Destination") { Text(destinationSummary) }
                LabeledContent("Schedule") { Text("Manual") }
            }

            Button {
            } label: {
                Label("Start Your First Backup", systemImage: "arrow.down.circle.fill")
                    .font(.title3)
            }
            .controlSize(.large)
            .disabled(true)

            Text("Coming in the next build.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Finish Setup") {
                if let plan = flow.makePlan() {
                    onFinish(plan)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var sourcesSummary: String {
        var parts: [String] = []
        let count = flow.sourceFolders.count
        if count > 0 {
            parts.append(count == 1 ? "1 folder" : "\(count) folders")
        }
        if flow.includePhotos {
            parts.append("Photos")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private var destinationSummary: String {
        flow.destination?.displayPath ?? "Not chosen"
    }
}
