import AppKit
import NoNeedCloudCore
import SwiftUI

/// The whole app in one window (UX spec §1–3): header, a status area that
/// changes with state, the always-visible "Your setup" list, and one primary
/// button that never moves.
struct MainWindowView: View {
    let model: AppModel
    @State private var activeSheet: SetupSheet?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    StatusArea(model: model, actions: actions)
                    YourSetupSection(model: model, actions: actions)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            PrimaryButtonBar(model: model)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .photos: PhotosSettingsSheet(model: model, actions: actions)
            case .folders: SourceFoldersSheet(model: model)
            case .destination: DestinationSheet(model: model)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.screenState)
    }

    private var actions: SetupActions {
        SetupActions(model: model, showSheet: { activeSheet = $0 })
    }
}

enum SetupSheet: String, Identifiable {
    case photos, folders, destination
    var id: String { rawValue }
}

/// The setup actions shared by the status cards and the "Your setup" rows.
@MainActor
struct SetupActions {
    let model: AppModel
    let showSheet: (SetupSheet) -> Void

    /// Asks for Photos access if needed, then turns the Photos source on.
    func enablePhotos() {
        Task {
            let granted: Bool
            if let known = PhotosAccess.isGranted {
                granted = known
            } else {
                granted = await PhotosAccess.request()
            }
            if granted {
                model.updatePlan { $0.photos.isEnabled = true }
            } else {
                PhotosAccess.openPrivacySettings()
            }
            await model.refreshHealth()
        }
    }

    func chooseFolders() {
        let folders = FolderPicker.chooseFolders(message: "Choose the folders you want to protect.", prompt: "Add")
        if !folders.isEmpty { model.addFolders(folders) }
    }

    func chooseDestination() {
        if let destination = FolderPicker.chooseDestination() {
            model.setDestination(destination)
        }
    }
}

private struct HeaderView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            Text("NoNeedCloud")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                openWindow(id: WindowID.history)
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help("Show backup history")
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct PrimaryButtonBar: View {
    let model: AppModel

    var body: some View {
        HStack {
            if let error = model.saveError {
                Label("Couldn't save your settings: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            if model.isRunning {
                Button(role: .cancel) {
                    model.stopBackup()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    model.startBackup()
                } label: {
                    Label("Start Backup", systemImage: "arrow.down.to.line")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStartBackup)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}
