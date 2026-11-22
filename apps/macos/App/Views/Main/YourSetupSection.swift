import NoNeedCloudCore
import SwiftUI

/// The always-visible configuration list (UX spec §2). Shows what's missing
/// explicitly so the user can see setup fill up.
struct YourSetupSection: View {
    let model: AppModel
    let actions: SetupActions
    @State private var showingSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your setup")
                .font(.headline)

            VStack(spacing: 0) {
                SetupRow(
                    systemImage: "photo.on.rectangle.angled",
                    title: "Photos",
                    value: photosValue,
                    isMissing: !model.plan.hasSources
                ) {
                    Button("Configure…") { actions.showSheet(.photos) }
                    Toggle("Back up Photos", isOn: photosToggle)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider().padding(.leading, 44)
                SetupRow(
                    systemImage: "folder",
                    title: "Files",
                    value: filesValue,
                    isMissing: !model.plan.hasSources
                ) {
                    Button("Configure…") { actions.showSheet(.folders) }
                    Toggle("Back up folders", isOn: model.planBinding(\.files.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(model.plan.files.folders.isEmpty)
                }
                Divider().padding(.leading, 44)
                SetupRow(
                    systemImage: "externaldrive",
                    title: "Destination",
                    value: model.plan.destination?.displayName ?? "Not configured",
                    isMissing: model.plan.destination == nil
                ) {
                    Button("Configure…") { actions.showSheet(.destination) }
                }
                Divider().padding(.leading, 44)
                SetupRow(
                    systemImage: "calendar.badge.clock",
                    title: "Schedule",
                    value: Formatting.schedule(model.plan.schedule),
                    isMissing: false
                ) {
                    Button("Configure…") { showingSchedule.toggle() }
                        .popover(isPresented: $showingSchedule, arrowEdge: .bottom) {
                            SchedulePopover(model: model)
                        }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .disabled(model.isRunning)
        }
    }

    private var photosValue: String {
        guard model.plan.photos.isEnabled else { return "Off" }
        if model.health.photosAccessGranted == false { return "No access" }
        if model.protectedPhotos > 0 { return Formatting.items(model.protectedPhotos) }
        return "On"
    }

    private var filesValue: String {
        let folders = model.plan.files.folders
        if folders.isEmpty { return "Not configured" }
        guard model.plan.files.isEnabled else { return "Off" }
        let count = folders.count == 1 ? folders[0].displayName : "\(folders.count) folders"
        if model.protectedFiles > 0 { return "\(count) · \(Formatting.items(model.protectedFiles))" }
        return count
    }

    /// Turning Photos on goes through the permission prompt.
    private var photosToggle: Binding<Bool> {
        Binding(
            get: { model.plan.photos.isEnabled },
            set: { isOn in
                if isOn {
                    actions.enablePhotos()
                } else {
                    model.updatePlan { $0.photos.isEnabled = false }
                }
            }
        )
    }
}

private struct SetupRow<Controls: View>: View {
    let systemImage: String
    let title: String
    let value: String
    let isMissing: Bool
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(title)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .foregroundStyle(isMissing && (value == "Not configured" || value == "Off") ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
