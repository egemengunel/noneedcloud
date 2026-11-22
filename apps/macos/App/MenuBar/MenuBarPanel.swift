import AppKit
import NoNeedCloudCore
import SwiftUI

// Menu bar panel, Figma "NoNeedCloud · macOS Menü çubuğu": a 348 pt panel
// showing the same state as the main window. Shown by StatusItemController.

struct MenuBarPanel: View {
    let model: AppModel
    let router: AppRouter
    /// Called after an action that should close the panel.
    var onAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 10) {
                stateCard
                primaryAction
            }
            .padding(.horizontal, 13)
            .padding(.top, 4)
            .animation(.smooth(duration: 0.25), value: model.screenState)
            bottomActions
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 6)
        }
        .frame(width: 348)
        .background(Theme.card)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if case .protected = model.screenState {
                Wordmark(height: 18.7)
            } else {
                HStack(spacing: 10) {
                    BrandCloud(color: Theme.ink, width: 24)
                    Text(verbatim: "NoNeedCloud")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            Spacer()
            Menu {
                Button("Settings…") { router.openSettings?(); onAction() }
                Divider()
                Button("Quit NoNeedCloud") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.lightLine))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings and Quit")
        }
        .padding(.leading, 17)
        .padding(.trailing, 14)
        .frame(height: 56)
    }

    // MARK: State card

    @ViewBuilder
    private var stateCard: some View {
        switch model.screenState {
        case .running:
            if let progress = model.progress {
                RunningCard(progress: progress, destinationName: Formatting.destinationName(model.plan))
            }
        case .protected:
            protectedCard
        case let .needsAttention(issue):
            attentionCard(issue)
        case .setup:
            setupCard
        }
    }

    private var protectedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusPill(text: String(localized: "Backup up to date"))
            Text(model.lastCompletedRun.map { String(localized: "Last backup \(Formatting.dayAndTime($0.finishedAt))") }
                 ?? String(localized: "Protected"))
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.52)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 12)
            Label {
                Text(Formatting.destinationName(model.plan))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: Formatting.kindSymbol(model.plan.destinationDetails))
                    .foregroundStyle(Theme.blue)
            }
            .padding(.top, 10)
            Text(model.nextScheduledRun.map { String(localized: "Next backup \(Formatting.nextRun($0).lowercased())") }
                 ?? String(localized: "No backup scheduled"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blueTint, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.blueLine))
    }

    private func attentionCard(_ issue: AttentionIssue) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusPill(text: String(localized: "Needs attention"), color: Theme.amber, background: Theme.amberTint)
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.amber)
            }
            Text(MenuBarText.attentionTitle(issue, destination: Formatting.destinationName(model.plan)))
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.52)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 10)
            Text(MenuBarText.attentionDetail(issue))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let run = model.lastCompletedRun {
                Text("Last successful backup \(Formatting.dayAndTime(run.finishedAt))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberTint, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.amberLine))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusPill(text: String(localized: "Not set up yet"), color: Theme.blue, background: Theme.card)
            Text("Finish setting up")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.52)
                .foregroundStyle(Theme.ink)
            Text("Choose what to protect and where to keep it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blueTint, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.blueLine))
    }

    // MARK: Primary action

    @ViewBuilder
    private var primaryAction: some View {
        switch model.screenState {
        case .running:
            fullWidth("Stop", style: .stop) { model.stopBackup() }
        case .protected:
            fullWidth("Back Up Now", style: .primary) { model.startBackup() }
                .disabled(!model.canStartBackup)
        case let .needsAttention(issue):
            switch issue {
            case .destinationUnavailable:
                fullWidth("Check Connection", style: .primary) { Task { await model.refreshHealth() } }
            case .photosAccessDenied:
                fullWidth("Open Privacy Settings", style: .primary) { PhotosAccess.openPrivacySettings() }
            case .lastRunFailed:
                fullWidth("Try Again", style: .primary) { model.startBackup() }
                    .disabled(!model.canStartBackup)
            case .backupStale:
                fullWidth("Back Up Now", style: .primary) { model.startBackup() }
                    .disabled(!model.canStartBackup)
            }
        case .setup:
            fullWidth("Continue Setup", style: .primary) { router.showMainWindow(); onAction() }
        }
    }

    private func fullWidth(_ title: LocalizedStringKey, style: PillButtonStyle.Kind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle(kind: style))
    }

    // MARK: Bottom actions (Menü Çubuğu / Alt eylemler)

    private var bottomActions: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            MenuActionRow(systemImage: "macbook", title: "Open NoNeedCloud", weight: .semibold) {
                router.showMainWindow()
                onAction()
            }
            Rectangle().fill(Theme.lightLine).frame(height: 1).padding(.leading, 37).padding(.trailing, 4)
            MenuActionRow(systemImage: "clock", title: "Backup History", weight: .medium) {
                router.showMainWindow(history: true)
                onAction()
            }
        }
    }
}

private struct MenuActionRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let weight: Font.Weight
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13, weight: weight))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)
            .frame(height: 40)
            .background(hovering ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Navy live-progress card (Aktif · Canlı ilerleme), compact version of the main window's.
private struct RunningCard: View {
    let progress: BackupProgress
    let destinationName: String

    private var percent: Int { Int(((progress.fractionCompleted ?? 0) * 100).rounded(.down)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Theme.lively).frame(width: 6, height: 6)
                Text(progress.phase == .enumerating ? "Scanning your sources" : "Backing up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.lightBlue)
            }
            HStack(alignment: .center) {
                Text(progress.fractionCompleted == nil ? "–" : (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-1.6)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(.snappy(duration: 0.35), value: percent)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(progress.estimatedRemaining.map(Formatting.remaining) ?? String(localized: "Estimating time left…"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    if let left = progress.remainingItems {
                        Text("\(Formatting.count(left)) items left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.lightBlue)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.top, 4)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.navyLine)
                    Capsule().fill(Theme.lively)
                        .frame(width: max(6, proxy.size.width * (progress.fractionCompleted ?? 0)))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.2), value: progress.fractionCompleted)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: progress.currentItem?.kind == .file ? "doc" : "photo")
                    .foregroundStyle(.white)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.currentItem.map { ($0.displayPath as NSString).lastPathComponent } ?? " ")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(progress.currentItem.map { Formatting.stage($0.stage, kind: $0.kind, destination: destinationName) } ?? " ")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.lightBlue)
                        .contentTransition(.opacity)
                }
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.18), value: progress.currentItem?.displayPath)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 43)
            .background(Theme.navy2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.navyLine))
            .padding(.top, 13)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 15))
        .environment(\.colorScheme, .dark)
    }
}

enum MenuBarText {
    static func attentionTitle(_ issue: AttentionIssue, destination: String) -> String {
        switch issue {
        case .destinationUnavailable: String(localized: "Can't reach \(destination)")
        case .photosAccessDenied: String(localized: "Photos access is off")
        case .lastRunFailed: String(localized: "The last backup didn't finish")
        case let .backupStale(days): String(localized: "No backup in \(days) days")
        }
    }

    static func attentionDetail(_ issue: AttentionIssue) -> String {
        switch issue {
        case .destinationUnavailable: String(localized: "Backups wait until the destination is connected again.")
        case .photosAccessDenied: String(localized: "NoNeedCloud can't read your Photos library, so photos aren't being backed up.")
        case let .lastRunFailed(reason): reason
        case .backupStale: String(localized: "Run a backup to bring your copy up to date.")
        }
    }
}
