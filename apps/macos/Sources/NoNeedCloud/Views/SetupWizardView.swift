import SwiftUI

struct SetupWizardView: View {
    @StateObject private var flow = SetupFlow()
    let onStartBackup: (BackupPlan) -> Void

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
        case .startBackup: StartBackupStep(flow: flow, onStartBackup: onStartBackup)
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
    @ObservedObject var flow: SetupFlow

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

            if flow.sourceFolderURLs.isEmpty {
                Text("No folders selected yet.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(flow.sourceFolderURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            Text(url.lastPathComponent)
                            Spacer()
                            Button {
                                flow.removeSourceFolder(url)
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
        if let url = FolderPicker.chooseDirectory() {
            flow.addSourceFolder(url)
        }
    }
}

struct DestinationStep: View {
    @ObservedObject var flow: SetupFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a folder on a drive you own. It should stay connected during backups.")
                .foregroundStyle(.secondary)

            Button("Choose Folder…") { chooseDestination() }

            if let url = flow.destinationURL {
                Text(url.path(percentEncoded: false))
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
    }

    private func chooseDestination() {
        if let url = FolderPicker.chooseDirectory() {
            flow.destinationURL = url
        }
    }
}

struct StartBackupStep: View {
    @ObservedObject var flow: SetupFlow
    let onStartBackup: (BackupPlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Sources") { Text(sourcesSummary) }
                LabeledContent("Destination") { Text(destinationSummary) }
                LabeledContent("Schedule") { Text("Manual") }
            }

            Button {
                if let plan = flow.makePlan() {
                    onStartBackup(plan)
                }
            } label: {
                Label("Start Your First Backup", systemImage: "arrow.down.circle.fill")
                    .font(.title3)
            }
            .controlSize(.large)
            .disabled(flow.makePlan() == nil)

            Text("Your backup runs right away, then only changed files are copied next time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var sourcesSummary: String {
        var parts: [String] = []
        let count = flow.sourceFolderURLs.count
        if count > 0 {
            parts.append(count == 1 ? "1 folder" : "\(count) folders")
        }
        if flow.includePhotos {
            parts.append("Photos")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private var destinationSummary: String {
        flow.destinationURL?.path(percentEncoded: false) ?? "Not chosen"
    }
}
