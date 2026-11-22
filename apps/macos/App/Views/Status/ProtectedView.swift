import NoNeedCloudCore
import SwiftUI

/// Figma "02 · Koruma özeti": hero with the last backup, archive status
/// tiles, and the backup plan with the next scheduled run.
struct ProtectedView: View {
    let model: AppModel
    let actions: SetupActions
    @State private var showingSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            SectionTitle("Archive status")
                .padding(.top, 20)
                .padding(.bottom, 9)
            HStack(spacing: 13) {
                MetricTile(
                    value: model.plan.photos.isEnabled ? Formatting.count(model.protectedPhotos) : "–",
                    title: String(localized: "Photos & videos"),
                    caption: String(localized: "Copies in the archive")
                )
                MetricTile(
                    value: model.plan.files.isEnabled ? Formatting.count(model.protectedFiles) : "–",
                    title: String(localized: "Files"),
                    caption: filesCaption
                )
                MetricTile(
                    value: Formatting.bytes(model.archiveBytes),
                    title: String(localized: "Total size"),
                    caption: destinationName
                )
                MetricTile(
                    value: model.protectedSince?.formatted(.dateTime.day().month(.abbreviated)) ?? "–",
                    title: String(localized: "First successful backup"),
                    caption: model.protectedSince.map { String(localized: "Since \($0.formatted(.dateTime.year()))") } ?? ""
                )
            }
            SectionTitle("Backup plan", size: 17)
                .padding(.top, 22)
                .padding(.bottom, 9)
            HStack(alignment: .top, spacing: 20) {
                GroupList {
                    GroupListRow(
                        systemImage: "folder",
                        title: String(localized: "Sources"),
                        subtitle: Formatting.sourcesSummary(model.plan),
                        showsChevron: true,
                        action: { actions.showSheet(.folders) }
                    )
                    GroupListRow(
                        systemImage: "externaldrive",
                        iconColor: Theme.green,
                        title: String(localized: "Destination"),
                        subtitle: "\(destinationName)  ·  \(connectionText)",
                        showsChevron: true,
                        action: { actions.showSheet(.destination) }
                    )
                }
                nextBackupCard
                    .frame(width: 300)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationName: String {
        Formatting.destinationName(model.plan)
    }

    private var connectionText: String {
        switch model.plan.destinationDetails?.kind {
        case .network:
            let proto = model.plan.destinationDetails?.networkProtocol ?? ""
            return proto.isEmpty ? String(localized: "Connected") : String(localized: "\(proto) connected")
        default:
            return String(localized: "Connected")
        }
    }

    private var filesCaption: String {
        let folders = model.plan.files.folders
        if folders.count == 1 { return Formatting.folderName(folders[0]) }
        return String(localized: "\(folders.count) folders")
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            HeroArtwork()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    StatusPill(text: String(localized: "Backup up to date"))
                    Text(headline(now: context.date))
                        .font(.system(size: 37, weight: .bold))
                        .tracking(-0.99)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 14)
                    Text("\(Formatting.sourcesSummary(model.plan))  →  \(destinationName)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 9)
                    Button("Back Up Now") { model.startBackup() }
                        .buttonStyle(.pillPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canStartBackup)
                        .padding(.top, 14)
                }
                .padding(.leading, 23)
                .padding(.top, 18)
                .padding(.trailing, 260)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Theme.blueTint)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.blueLine))
    }

    private func headline(now: Date) -> String {
        guard let run = model.lastCompletedRun else { return String(localized: "Protected") }
        return String(localized: "Last backup \(Formatting.dayAndTime(run.finishedAt, now: now))")
    }

    // MARK: Next backup

    private var nextBackupCard: some View {
        Button { showingSchedule = true } label: {
            HStack(alignment: .top, spacing: 13) {
                IconBadge(systemImage: "calendar")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next backup")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 5)
                    Text(model.nextScheduledRun.map { Formatting.nextRun($0) } ?? String(localized: "Not scheduled"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 5)
                    Text(model.plan.schedule.frequency == .off
                         ? String(localized: "Choose a schedule")
                         : "\(Formatting.frequency(model.plan.schedule))  ·  \(String(localized: "On this Mac"))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 11)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            }
            .padding(.leading, 14)
            .padding(.trailing, 17)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.lightLine))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSchedule, arrowEdge: .top) {
            SchedulePopover(model: model)
        }
    }
}

/// Orbits, cloud and check on the right of the protected hero, placed at the
/// exact Figma coordinates ("02 · Koruma özeti", hero card 944 × 200),
/// measured from the card's trailing edge so they hold at any window width.
private struct HeroArtwork: View {
    /// Figma card width the coordinates below are measured in.
    private let designWidth: CGFloat = 944

    var body: some View {
        GeometryReader { proxy in
            let x = { (designX: CGFloat) in proxy.size.width - (designWidth - designX) }
            ZStack {
                Circle().fill(Theme.heroOrbitOuter).frame(width: 272, height: 272)
                    .position(x: x(904), y: 95)
                Circle().fill(Theme.heroOrbitInner).frame(width: 235, height: 235)
                    .position(x: x(837.5), y: 119.5)
                Circle().fill(Theme.heroCloudBase).frame(width: 159, height: 159)
                    .position(x: x(820.5), y: 99.5)
                BrandCloud(color: Theme.blue, width: 96)
                    .position(x: x(819), y: 97)
                Circle().fill(.white).frame(width: 35, height: 35)
                    .position(x: x(867.5), y: 123.5)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.green)
                    .position(x: x(867.5), y: 123.5)
            }
        }
        .accessibilityHidden(true)
    }
}
