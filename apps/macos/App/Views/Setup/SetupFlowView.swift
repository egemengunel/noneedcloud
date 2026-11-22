import NoNeedCloudCore
import SwiftUI

/// First setup, Figma "01 · İlk kurulum": a step list on the left, the
/// current step on the right, Back / Continue in the footer.
struct SetupFlowView: View {
    let model: AppModel
    let reached: SetupStep
    let actions: SetupActions
    @State private var requested: SetupStep?
    @State private var showingSchedule = false

    init(model: AppModel, reached: SetupStep, actions: SetupActions, initialStep: SetupStep? = nil) {
        self.model = model
        self.reached = reached
        self.actions = actions
        _requested = State(initialValue: initialStep)
    }

    private var step: SetupStep { MainScreenState.visibleStep(requested: requested, reached: reached) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 39) {
                StepSidebar(model: model, step: step, reached: reached)
                    .frame(width: 245)
                Group {
                    switch step {
                    case .sources: SourcesStepView(model: model, actions: actions)
                    case .destination: DestinationStepView(model: model, actions: actions)
                    case .firstBackup:
                        ReviewStepView(model: model, showingSchedule: $showingSchedule) { requested = $0 }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 3)
            }
            .padding(.top, 25)
            Spacer(minLength: 16)
            WindowFooter {
                if step != .sources {
                    Button("Back") { requested = SetupStep(rawValue: step.rawValue - 1) }
                        .buttonStyle(.pillSecondary)
                }
            } trailing: {
                primaryButton
            }
        }
        .padding(.horizontal, 24)
        .animation(.smooth(duration: 0.2), value: step)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .sources:
            Button("Choose Destination") { requested = .destination }
                .buttonStyle(.pillPrimary)
                .disabled(!model.plan.hasSources)
        case .destination:
            Button("Review First Backup") { requested = .firstBackup }
                .buttonStyle(.pillPrimary)
                .disabled(reached != .firstBackup || model.health.destination?.isWritable == false)
        case .firstBackup:
            Button("Start First Backup") { model.startBackup() }
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStartBackup)
        }
    }
}

private struct StepSidebar: View {
    let model: AppModel
    let step: SetupStep
    let reached: SetupStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandCloud(color: Theme.ink, width: 96)
            Text("First Setup")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Theme.ink)
                .padding(.top, 26)
            StepperList(items: items, spacing: 14)
                .padding(.top, 22)
            Spacer(minLength: 20)
            Text("Backup copies are kept on the storage you choose.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(25)
        .frame(maxWidth: .infinity, minHeight: 461, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.lightLine))
    }

    private var items: [StepperList.Item] {
        [
            .init(id: 1, title: String(localized: "Sources"),
                  subtitle: model.plan.hasSources ? Formatting.sourcesSummary(model.plan) : String(localized: "Choose what to protect"),
                  state: state(.sources)),
            .init(id: 2, title: String(localized: "Destination"),
                  subtitle: model.plan.destination.map { _ in model.plan.destinationDetails?.volumeName ?? model.plan.destination!.displayName }
                      ?? String(localized: "Choose storage"),
                  state: state(.destination)),
            .init(id: 3, title: String(localized: "First Backup"), subtitle: String(localized: "Review and start"),
                  state: state(.firstBackup)),
        ]
    }

    private func state(_ item: SetupStep) -> StepperList.Item.State {
        if item == step { return .current }
        return item.rawValue < reached.rawValue ? .done : .upcoming
    }
}

/// Shared title + subtitle at the top of each step (31 pt bold, 15 pt muted).
private struct StepHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 31, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct InfoLine: View {
    let text: LocalizedStringKey
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "info.circle") }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.muted)
    }
}

// MARK: - Step 1: Sources

private struct SourcesStepView: View {
    let model: AppModel
    let actions: SetupActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Choose what to protect", subtitle: "NoNeedCloud keeps an independent copy of what you pick.")

            Text("Library")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
                .padding(.bottom, 10)
            GroupList {
                GroupListRow(
                    systemImage: "photo.on.rectangle.angled",
                    title: String(localized: "Photos"),
                    subtitle: photosSubtitle
                ) {
                    if model.plan.photos.isEnabled {
                        Button("Options…") { actions.showSheet(.photos) }
                            .buttonStyle(.link)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Toggle("Back up Photos", isOn: photosBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Text("Folders")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)
                .padding(.bottom, 10)
            GroupList {
                ForEach(model.plan.files.folders, id: \.displayPath) { folder in
                    GroupListRow(
                        systemImage: Formatting.isICloud(folder) ? "icloud" : "folder",
                        title: Formatting.folderName(folder),
                        subtitle: folder.displayPath
                    ) {
                        Button {
                            model.removeFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.subtle)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
                GroupListRow(
                    systemImage: "plus",
                    title: String(localized: "Add Folder"),
                    subtitle: String(localized: "iCloud Drive, Desktop & Documents or any folder"),
                    showsChevron: true,
                    action: actions.chooseFolders
                )
            }

            InfoLine(text: "Nothing in iCloud is ever changed. NoNeedCloud only reads.")
                .padding(.top, 20)
        }
    }

    private var photosSubtitle: String {
        if model.plan.photos.isEnabled, model.health.photosAccessGranted == false {
            return String(localized: "Access is off in System Settings")
        }
        return String(localized: "Originals, edits and Live Photos")
    }

    private var photosBinding: Binding<Bool> {
        Binding(
            get: { model.plan.photos.isEnabled },
            set: { isOn in
                if isOn { actions.enablePhotos() } else { model.updatePlan { $0.photos.isEnabled = false } }
            }
        )
    }
}

// MARK: - Step 2: Destination

private struct DestinationStepView: View {
    let model: AppModel
    let actions: SetupActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Choose a backup destination", subtitle: "Pick separate storage for your originals.")

            if let destination = model.plan.destination {
                SelectedDestinationCard(
                    name: model.plan.destinationDetails?.volumeName ?? destination.displayName,
                    folder: destination.displayName,
                    details: model.plan.destinationDetails,
                    isAvailable: model.health.destinationAvailable
                )
                .padding(.top, 23)
            }

            Text(model.plan.destination == nil ? "Destinations" : "Other destinations")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
                .padding(.bottom, 8)
            GroupList {
                GroupListRow(
                    systemImage: "internaldrive",
                    title: String(localized: "External Disk"),
                    subtitle: String(localized: "USB or Thunderbolt"),
                    showsChevron: true,
                    action: actions.chooseDestination
                )
                GroupListRow(
                    systemImage: "plus",
                    title: String(localized: "Add Network Location"),
                    subtitle: String(localized: "Connect to a NAS over SMB"),
                    showsChevron: true,
                    action: actions.chooseNetworkDestination
                )
            }

            InfoLine(text: "Backups are plain files and folders you can open in Finder.")
                .padding(.top, 20)
        }
    }
}

/// The highlighted destination card (Seçili hedef).
struct SelectedDestinationCard: View {
    let name: String
    let folder: String
    let details: DestinationDetails?
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemImage: Formatting.kindSymbol(details))
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                badge.padding(.top, 6)
            }
            Spacer()
            HStack(spacing: 8) {
                if let free = details?.freeBytes, isAvailable {
                    Text("\(Formatting.bytes(free)) free")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.blue)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blueTint, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Theme.blueLine))
    }

    private var subtitle: String {
        let kind = Formatting.kind(details)
        return name == folder ? kind : "\(kind)  ·  \(folder)"
    }

    @ViewBuilder
    private var badge: some View {
        if !isAvailable {
            StatusPill(text: String(localized: "Not connected"), color: Theme.amber, background: Theme.amberTint)
        } else if details?.isWritable == false {
            StatusPill(text: String(localized: "Read only"), color: Theme.red, background: Theme.amberTint)
        } else {
            StatusPill(text: String(localized: "Write access"))
        }
    }
}

// MARK: - Step 3: Review

private struct ReviewStepView: View {
    let model: AppModel
    @Binding var showingSchedule: Bool
    let goTo: (SetupStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Review your first backup", subtitle: "Check what's copied where, then start.")

            GroupList {
                GroupListRow(
                    systemImage: "folder",
                    title: String(localized: "Sources"),
                    subtitle: Formatting.sourcesSummary(model.plan),
                    showsChevron: true,
                    action: { goTo(.sources) }
                )
                GroupListRow(
                    systemImage: Formatting.kindSymbol(model.plan.destinationDetails),
                    iconColor: Theme.green,
                    title: String(localized: "Destination"),
                    subtitle: destinationSubtitle,
                    showsChevron: true,
                    action: { goTo(.destination) }
                )
                GroupListRow(
                    systemImage: "calendar",
                    title: String(localized: "Schedule"),
                    subtitle: Formatting.schedule(model.plan.schedule),
                    showsChevron: true,
                    action: { showingSchedule = true }
                )
                    .popover(isPresented: $showingSchedule, arrowEdge: .trailing) {
                        SchedulePopover(model: model)
                    }
            }
            .padding(.top, 23)

            VStack(alignment: .leading, spacing: 9) {
                Text("Before you start")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                ChecklistLine(text: "The first backup copies everything and can take a while.")
                ChecklistLine(text: "Keep your Mac awake and plugged in.")
                ChecklistLine(text: "You can stop any time. The next run picks up where it left off.")
            }
            .padding(.top, 22)
        }
    }

    private var destinationSubtitle: String {
        let name = model.plan.destinationDetails?.volumeName ?? model.plan.destination?.displayName ?? ""
        return "\(name)  ·  \(Formatting.kind(model.plan.destinationDetails))"
    }
}

private struct ChecklistLine: View {
    let text: LocalizedStringKey
    var body: some View {
        Label { Text(text) } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.green)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.muted)
    }
}
