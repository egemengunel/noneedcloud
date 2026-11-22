import NoNeedCloudCore
import SwiftUI

struct PhotosSettingsSheet: View {
    let model: AppModel
    let actions: SetupActions
    @State private var showingMirroring = false

    var body: some View {
        SheetChrome(
            title: "Photos",
            subtitle: "Choose what to copy from your Photos library. Originals are always copied at full quality."
        ) {
            Form {
                Section {
                    Toggle("Back up Photos", isOn: enabledBinding)
                    if model.health.photosAccessGranted == false {
                        HStack {
                            Label("NoNeedCloud doesn't have access to Photos.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings") { PhotosAccess.openPrivacySettings() }
                        }
                    }
                }
                Section("Include") {
                    Toggle("Photos", isOn: model.planBinding(\.photos.includePhotos))
                    Toggle("Videos", isOn: model.planBinding(\.photos.includeVideos))
                    Toggle("Edited versions alongside originals", isOn: model.planBinding(\.photos.includeEdits))
                    Toggle("Shared Albums", isOn: model.planBinding(\.photos.includeSharedAlbums))
                }
                .disabled(!model.plan.photos.isEnabled)
                Section {
                    LabeledContent("Mirroring") {
                        Button(mirroringSummary) { showingMirroring.toggle() }
                            .popover(isPresented: $showingMirroring, arrowEdge: .trailing) {
                                MirroringPopover(model: model)
                            }
                    }
                } footer: {
                    Text("By default your backup only grows. With mirroring, items you delete are moved to a Deleted folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } secondary: {
            Button("Reset to Defaults") {
                model.updatePlan { plan in
                    let isEnabled = plan.photos.isEnabled
                    plan.photos = .defaults
                    plan.photos.isEnabled = isEnabled
                    plan.mirroring = MirroringSettings()
                }
            }
        }
        .frame(height: 520)
    }

    private var mirroringSummary: String {
        model.plan.mirroring.isEnabled ? Formatting.retention(model.plan.mirroring.retention) : "Off"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.plan.photos.isEnabled },
            set: { isOn in
                if isOn { actions.enablePhotos() } else { model.updatePlan { $0.photos.isEnabled = false } }
            }
        )
    }
}

/// Mirroring + retention (UX spec §8). The Deleted-folder size and
/// "Empty Now" arrive with the mirroring engine in M8.
struct MirroringPopover: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mirror deletions", isOn: model.planBinding(\.mirroring.isEnabled))
                .toggleStyle(.switch)
                .font(.headline)
            Text("When you delete something from Photos or a source folder, NoNeedCloud moves its copy to a Deleted folder at the destination instead of keeping it in the backup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Deleted items", selection: model.planBinding(\.mirroring.retention)) {
                ForEach(MirroringSettings.Retention.allCases, id: \.self) { retention in
                    Text(Formatting.retention(retention)).tag(retention)
                }
            }
            .disabled(!model.plan.mirroring.isEnabled)
            Divider()
            HStack {
                Text("Deleted folder: empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Empty Now", role: .destructive) {}
                    .disabled(true)
                    .help("Available once mirroring runs")
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}
