import AppKit
import NoNeedCloudCore
import SwiftUI

/// Figma "04 · Bağlantı sorunu", generalised to every attention issue:
/// amber banner, fix-it steps, the last successful backup, two actions.
struct AttentionView: View {
    let model: AppModel
    let issue: AttentionIssue
    let actions: SetupActions
    @Environment(\.openWindow) private var openWindow

    private var destinationName: String {
        model.plan.destinationDetails?.volumeName ?? model.plan.destination?.displayName ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            SectionTitle(LocalizedStringKey(stepsTitle), size: 20)
                .padding(.top, 25)
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 20) {
                GroupList { steps }
                lastBackupCard.frame(width: 304)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            WindowFooter {
                secondaryAction
            } trailing: {
                primaryAction
            }
        }
    }

    // MARK: Banner

    private var banner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconBadge(systemImage: "exclamationmark.triangle", color: Theme.amber, background: Theme.amberTint)
                StatusPill(text: String(localized: "Needs attention"), color: Theme.amber, background: Theme.amberTint)
            }
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.68)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberTint, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.amberLine))
    }

    private var lastSuccess: String {
        guard let run = model.lastCompletedRun else { return "" }
        return String(localized: "Last successful backup \(Formatting.dayAndTime(run.finishedAt)).")
    }

    private var title: String {
        switch issue {
        case .destinationUnavailable: String(localized: "Can't reach \(destinationName)")
        case .photosAccessDenied: String(localized: "Photos access is off")
        case .lastRunFailed: String(localized: "The last backup didn't finish")
        case let .backupStale(days): String(localized: "No backup in \(days) days")
        }
    }

    private var detail: String {
        switch issue {
        case .destinationUnavailable:
            "\(lastSuccess) \(String(localized: "Backups wait until the destination is connected again."))"
        case .photosAccessDenied:
            String(localized: "NoNeedCloud can't read your Photos library, so photos aren't being backed up.")
        case let .lastRunFailed(reason):
            "\(reason) \(lastSuccess)"
        case .backupStale:
            "\(lastSuccess) \(String(localized: "Run a backup to bring your copy up to date."))"
        }
    }

    // MARK: Steps

    private var stepsTitle: String {
        switch issue {
        case .destinationUnavailable: String(localized: "Fix the connection")
        case .photosAccessDenied: String(localized: "Turn access back on")
        case .lastRunFailed, .backupStale: String(localized: "Get back on track")
        }
    }

    @ViewBuilder
    private var steps: some View {
        switch issue {
        case .destinationUnavailable:
            if model.plan.destinationDetails?.kind == .network {
                GroupListRow(
                    systemImage: "wifi", iconColor: Theme.amber,
                    title: String(localized: "Check your network connection"),
                    subtitle: String(localized: "Connect this Mac to the same network as \(destinationName).")
                )
                GroupListRow(
                    systemImage: "externaldrive", iconColor: Theme.amber,
                    title: String(localized: "Make sure \(destinationName) is on"),
                    subtitle: String(localized: "Check the network drive's power and network cable.")
                )
                reconnectRow
            } else {
                GroupListRow(
                    systemImage: "cable.connector", iconColor: Theme.amber,
                    title: String(localized: "Connect \(destinationName)"),
                    subtitle: String(localized: "Plug the drive into this Mac and wait for it to appear in Finder.")
                )
                GroupListRow(
                    systemImage: "lock.open", iconColor: Theme.amber,
                    title: String(localized: "Unlock it if it's encrypted"),
                    subtitle: String(localized: "Finder asks for the drive's password when it's connected.")
                )
                GroupListRow(
                    systemImage: "folder",
                    title: String(localized: "Open Volumes in Finder"),
                    subtitle: String(localized: "See which drives are connected."),
                    showsChevron: true,
                    action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes")) }
                )
            }
        case .photosAccessDenied:
            GroupListRow(
                systemImage: "gearshape", iconColor: Theme.amber,
                title: String(localized: "Open Privacy & Security"),
                subtitle: String(localized: "System Settings → Privacy & Security → Photos"),
                showsChevron: true,
                action: PhotosAccess.openPrivacySettings
            )
            GroupListRow(
                systemImage: "checkmark.circle", iconColor: Theme.amber,
                title: String(localized: "Turn on NoNeedCloud"),
                subtitle: String(localized: "Choose Full Access so originals can be copied.")
            )
        case .lastRunFailed, .backupStale:
            GroupListRow(
                systemImage: Formatting.kindSymbol(model.plan.destinationDetails), iconColor: Theme.amber,
                title: String(localized: "Connect \(destinationName)"),
                subtitle: String(localized: "Make sure the destination is available and has free space.")
            )
            GroupListRow(
                systemImage: "bolt", iconColor: Theme.amber,
                title: String(localized: "Keep your Mac awake"),
                subtitle: String(localized: "Plug it in so long backups aren't interrupted.")
            )
            GroupListRow(
                systemImage: "clock.arrow.circlepath",
                title: String(localized: "See what happened"),
                subtitle: String(localized: "Backup history lists every run and missed item."),
                showsChevron: true,
                action: { openWindow(id: WindowID.history) }
            )
        }
    }

    @ViewBuilder
    private var reconnectRow: some View {
        let remount = model.plan.destinationDetails?.remountURL
        VStack(alignment: .leading, spacing: 0) {
            GroupListRow(
                systemImage: "folder",
                title: String(localized: "Connect to the server in Finder"),
                subtitle: String(localized: "Reopen the network location."),
                showsChevron: true,
                action: {
                    if let remount, let url = URL(string: remount) { NSWorkspace.shared.open(url) }
                }
            )
            if let remount {
                Text(remount)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .padding(.leading, 68)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: Last backup

    private var lastBackupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconBadge(systemImage: "checkmark.seal", color: Theme.green, background: Theme.mint)
            Text("Last successful backup")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 16)
            Text(model.lastCompletedRun.map { Formatting.dayCommaTime($0.finishedAt) } ?? String(localized: "None yet"))
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
            Text("\(Formatting.bytes(model.archiveBytes))  ·  \(destinationName)")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.top, 7)
            Text("Copies in the archive are available again once the destination reconnects.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Theme.lightLine))
    }

    // MARK: Actions

    @ViewBuilder
    private var secondaryAction: some View {
        switch issue {
        case .destinationUnavailable, .lastRunFailed, .backupStale:
            Button("Change Destination") { actions.chooseDestination() }
                .buttonStyle(.pillSecondary)
        case .photosAccessDenied:
            Button("Turn Off Photos Backup") { model.updatePlan { $0.photos.isEnabled = false } }
                .buttonStyle(.pillSecondary)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch issue {
        case .destinationUnavailable:
            Button("Check Connection") { Task { await model.refreshHealth() } }
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
        case .photosAccessDenied:
            Button("Open Privacy Settings") { PhotosAccess.openPrivacySettings() }
                .buttonStyle(.pillPrimary)
        case .lastRunFailed:
            Button("Try Again") { model.startBackup() }
                .buttonStyle(.pillPrimary)
                .disabled(!model.canStartBackup)
        case .backupStale:
            Button("Back Up Now") { model.startBackup() }
                .buttonStyle(.pillPrimary)
                .disabled(!model.canStartBackup)
        }
    }
}
