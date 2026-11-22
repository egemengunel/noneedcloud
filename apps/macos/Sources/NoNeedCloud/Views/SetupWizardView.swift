import SwiftUI

struct SetupWizardView: View {
    let onStartBackup: (BackupPlan) -> Void
    @StateObject private var flow: SetupFlow

    init(onStartBackup: @escaping (BackupPlan) -> Void, keychain: (any KeychainStore)? = nil) {
        self.onStartBackup = onStartBackup
        let setupFlow = SetupFlow()
        setupFlow.keychain = keychain
        _flow = StateObject(wrappedValue: setupFlow)
    }

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
                photoOptionsSection
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

            VStack(alignment: .leading, spacing: 8) {
                Text("iCloud Sources")
                    .font(.headline)
                Toggle("iCloud Drive", isOn: $flow.includeICloudDrive)
                if flow.includeICloudDrive {
                    Text("Includes Desktop and Documents when they sync with iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                Toggle("Pages", isOn: $flow.includePages)
                Toggle("Numbers", isOn: $flow.includeNumbers)
            }
        }
        .padding(20)
    }

    private var photoOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Photos Only", isOn: $flow.photosOnly)
            Toggle("Videos Only", isOn: $flow.videosOnly)
            Toggle("Include Edited Versions and Extra Components", isOn: $flow.includeEdits)
            Toggle("Include Shared Albums", isOn: $flow.includeSharedAlbums)
            Toggle("Limit to Date Range", isOn: $flow.usePhotoDateRange)
            if flow.usePhotoDateRange {
                DatePicker("From", selection: $flow.photoDateRangeStart, displayedComponents: .date)
                DatePicker("To", selection: $flow.photoDateRangeEnd, in: flow.photoDateRangeStart..., displayedComponents: .date)
            }
            Text("The System Photo Library is backed up at original quality, organized by date. iCloud assets are fetched on demand, one at a time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
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
            Picker("Destination Type", selection: $flow.destinationProvider) {
                ForEach(DestinationProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("destinationProvider")

            switch flow.destinationProvider {
            case .folder: folderSection
            case .s3: s3Section
            case .onedrive: tokenSection(title: "OneDrive Access Token", hint: Self.oneDriveHint)
            case .gdrive: tokenSection(title: "Google Drive Access Token", hint: Self.googleDriveHint)
            }

            if let error = flow.destinationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a folder on a drive you own. It should stay connected during backups.")
                .foregroundStyle(.secondary)
            Button("Choose Folder…") { chooseFolder() }
            if let url = flow.destinationURL {
                Text(url.path(percentEncoded: false))
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private var s3Section: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Works with AWS S3 and S3-compatible services (MinIO, Wasabi, Backblaze B2). Leave the endpoint empty for AWS.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("Bucket", text: $flow.s3Bucket)
                    .textFieldStyle(.roundedBorder)
                TextField("Endpoint URL (optional)", text: $flow.s3Endpoint)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                TextField("Region", text: $flow.s3Region)
                    .textFieldStyle(.roundedBorder)
                TextField("Key Prefix (optional)", text: $flow.s3Prefix)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                TextField("Access Key ID", text: $flow.s3AccessKeyID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret Access Key", text: $flow.s3SecretAccessKey)
                    .textFieldStyle(.roundedBorder)
            }
            SecureField("Session Token (optional)", text: $flow.s3SessionToken)
                .textFieldStyle(.roundedBorder)
            Toggle("Use Path-Style Requests (recommended for S3-compatible services)", isOn: $flow.s3UsePathStyle)
            Text("The secret key and session token are stored in your macOS Keychain and never written to disk by NoNeedCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tokenSection(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint)
                .foregroundStyle(.secondary)
            SecureField(title, text: $flow.cloudToken)
                .textFieldStyle(.roundedBorder)
            Text("The token is stored in your macOS Keychain. Access tokens expire — when a run reports HTTP 401, paste a fresh one here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static let oneDriveHint = "Paste a Microsoft Graph access token with the Files.ReadWrite scope. One way to get one: run \"az login\" and then \"az account get-access-token --resource https://graph.microsoft.com\" in a terminal."

    static let googleDriveHint = "Paste a Google OAuth access token with the Drive scope. One way to get one: open https://developers.google.com/oauthplayground, authorize Drive API v3 with the drive.file scope, and exchange it for an access token."

    private func chooseFolder() {
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

            if let error = flow.destinationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Your backup runs right away, then only changed files are copied next time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var sourcesSummary: String {
        var parts = flow.plannedSources.map(\.displayName)
        if flow.includePhotos {
            parts.append("Photos")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private var destinationSummary: String {
        flow.plannedDestination?.displayName ?? "Not chosen"
    }
}
