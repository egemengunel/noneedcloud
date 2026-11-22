import NoNeedCloudCore
import SwiftUI

/// The top of the main window; its content follows `MainScreenState`.
struct StatusArea: View {
    let model: AppModel
    let actions: SetupActions

    var body: some View {
        switch model.screenState {
        case let .setup(step):
            SetupStatusView(step: step, model: model, actions: actions)
        case .running:
            if let progress = model.progress {
                RunningStatusView(progress: progress)
            }
        case .protected:
            ProtectedStatusView(model: model, issue: nil, actions: actions)
        case let .needsAttention(issue):
            ProtectedStatusView(model: model, issue: issue, actions: actions)
        }
    }
}

// MARK: - Setup

struct SetupStatusView: View {
    let step: SetupStep
    let model: AppModel
    let actions: SetupActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SetupProgressBar(step: step)
            VStack(alignment: .leading, spacing: 14) {
                Text("Step \(step.rawValue) of 3")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var title: String {
        switch step {
        case .sources: "What to protect"
        case .destination: "Where to keep your data"
        case .firstBackup: "Start your first backup"
        }
    }

    private var explanation: String {
        switch step {
        case .sources:
            "iCloud keeps your devices in sync, but a deletion on one device removes it everywhere. "
                + "Pick what NoNeedCloud should keep an independent copy of. Nothing in iCloud is ever changed."
        case .destination:
            "Choose a folder on an external drive, a NAS or any volume you own. "
                + "Your backup is stored as plain files and folders you can open in Finder."
        case .firstBackup:
            "\(Formatting.sourcesSummary(model.plan)) → \(model.plan.destination?.displayName ?? "")"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .sources:
            HStack(spacing: 10) {
                Button("Allow Photos Access", systemImage: "photo.on.rectangle") { actions.enablePhotos() }
                Button("Choose Folders…", systemImage: "folder.badge.plus") { actions.chooseFolders() }
            }
            .controlSize(.large)
            .padding(.top, 4)
        case .destination:
            Button("Choose Destination…", systemImage: "externaldrive") { actions.chooseDestination() }
                .controlSize(.large)
                .padding(.top, 4)
        case .firstBackup:
            VStack(alignment: .leading, spacing: 8) {
                Text("The first backup copies everything and can take a while for a large library. Later runs only copy what's new or changed.")
                    .fixedSize(horizontal: false, vertical: true)
                ChecklistRow(text: "Keep your Mac awake and plugged in")
                ChecklistRow(text: "Prefer a drive connected directly to your Mac")
                ChecklistRow(text: "You can stop at any time; the next run picks up where it left off")
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }
}

private struct ChecklistRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
    }
}

/// Three segments: Sources → Destination → First backup.
struct SetupProgressBar: View {
    let step: SetupStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.self) { segment in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(segment.rawValue <= step.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(height: 5)
                    Text(label(segment))
                        .font(.caption)
                        .foregroundStyle(segment == step ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup step \(step.rawValue) of 3")
    }

    private func label(_ step: SetupStep) -> String {
        switch step {
        case .sources: "Sources"
        case .destination: "Destination"
        case .firstBackup: "First backup"
        }
    }
}

// MARK: - Running

struct RunningStatusView: View {
    let progress: BackupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(percentText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let remaining = progress.estimatedRemaining {
                        Text(Formatting.remaining(remaining))
                    } else {
                        Text(progress.phase == .enumerating ? "Looking for new items…" : "Estimating time…")
                    }
                    if let left = progress.remainingItems {
                        Text("\(Formatting.items(left)) to go")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }

            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            CurrentItemRow(item: progress.currentItem)

            LazyVGrid(columns: StatTile.columns, spacing: 12) {
                StatTile(
                    value: Formatting.count(progress.processedPhotos + progress.processedFiles),
                    label: "Protected so far",
                    systemImage: "checkmark.shield",
                    tint: .teal
                )
                TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                    StatTile(
                        value: Formatting.duration(context.date.timeIntervalSince(progress.startedAt)),
                        label: "Running for",
                        systemImage: "timer",
                        tint: .indigo
                    )
                }
                StatTile(
                    value: Formatting.count(progress.copiedItems),
                    label: "New items copied",
                    systemImage: "plus.square.on.square",
                    tint: .orange
                )
                StatTile(
                    value: progress.startedAt.formatted(date: .omitted, time: .shortened),
                    label: "Started at",
                    systemImage: "clock",
                    tint: .pink
                )
            }

            Label("Preview build: this backup is simulated and no files are copied.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentText: String {
        guard let fraction = progress.fractionCompleted else { return "–" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The file being worked on, with the four-stage indicator (UX spec §5.1).
struct CurrentItemRow: View {
    let item: BackupProgress.CurrentItem?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item?.kind == .photo ? "photo" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(item?.displayPath ?? " ")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let item {
                Text(Formatting.stage(item.stage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StageDots(current: item.stage, includesRelease: item.kind == .file)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StageDots: View {
    let current: BackupProgress.Stage
    let includesRelease: Bool

    private var stages: [BackupProgress.Stage] {
        includesRelease ? [.check, .fetch, .write, .release] : [.check, .fetch, .write]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(stages, id: \.self) { stage in
                Circle()
                    .fill(isReached(stage) ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private func isReached(_ stage: BackupProgress.Stage) -> Bool {
        (stages.firstIndex(of: stage) ?? 0) <= (stages.firstIndex(of: current) ?? 0)
    }
}

// MARK: - Protected / Needs attention

struct ProtectedStatusView: View {
    let model: AppModel
    let issue: AttentionIssue?
    let actions: SetupActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: issue == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue == nil ? Color.green : Color.orange)
                        Text(headline(now: context.date))
                    }
                    .font(.title.weight(.semibold))
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let issue {
                fixButton(for: issue)
                    .controlSize(.large)
            }

            // Before the first completed run there's nothing to show yet.
            if model.lastCompletedRun != nil {
                statistics
            }
        }
    }

    private var statistics: some View {
        LazyVGrid(columns: StatTile.columns, spacing: 12) {
                StatTile(
                    value: model.plan.photos.isEnabled ? Formatting.count(model.protectedPhotos) : "Off",
                    label: "Photos protected",
                    systemImage: "photo.stack",
                    tint: .teal
                )
                StatTile(
                    value: model.plan.files.isEnabled ? Formatting.count(model.protectedFiles) : "Off",
                    label: "Files protected",
                    systemImage: "doc.on.doc",
                    tint: .indigo
                )
                StatTile(
                    value: model.protectedSince?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "–",
                    label: "Protected since",
                    systemImage: "calendar",
                    tint: .orange
                )
                StatTile(
                    value: "+\(Formatting.count(model.addedSinceFirstRun))",
                    label: "Added since first run",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .pink
                )
                StatTile(
                    value: Formatting.bytes(model.totalBytesWritten),
                    label: "Copied to destination",
                    systemImage: "externaldrive",
                    tint: .mint
                )
                StatTile(
                    value: model.lastCompletedRun.map { Formatting.duration($0.duration) } ?? "–",
                    label: "Last run took",
                    systemImage: "stopwatch",
                    tint: .purple
                )
                StatTile(
                    value: Formatting.count(model.planRuns.filter(\.didComplete).count),
                    label: "Completed runs",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .blue
                )
                StatTile(
                    value: Formatting.count(model.lastRun?.failedItems ?? 0),
                    label: "Items missed last run",
                    systemImage: "exclamationmark.circle",
                    tint: (model.lastRun?.failedItems ?? 0) > 0 ? .orange : .gray
                )
        }
    }

    private func headline(now: Date) -> String {
        switch issue {
        case nil:
            guard let run = model.lastCompletedRun else { return "Protected" }
            return "Last backup \(Formatting.relative(run.finishedAt, now: now))"
        case .destinationUnavailable: return "Destination not available"
        case .photosAccessDenied: return "Photos access is off"
        case .lastRunFailed: return "The last backup didn't finish"
        case let .backupStale(days): return "No backup in \(days) days"
        }
    }

    private var detail: String {
        let context = "\(Formatting.sourcesSummary(model.plan)) → \(model.plan.destination?.displayName ?? "no destination")"
        switch issue {
        case nil:
            if let failed = model.lastRun?.failedItems, failed > 0 {
                return "\(context). \(Formatting.items(failed)) couldn't be copied and will be retried next time."
            }
            return context
        case let .destinationUnavailable(name):
            return "\"\(name)\" can't be found. Connect the drive or choose another destination."
        case .photosAccessDenied:
            return "NoNeedCloud needs access to your Photos library to back it up. Turn it on in System Settings → Privacy & Security → Photos."
        case let .lastRunFailed(reason):
            return reason
        case .backupStale:
            return "\(context). Run a backup now to keep your copy up to date."
        }
    }

    @ViewBuilder
    private func fixButton(for issue: AttentionIssue) -> some View {
        switch issue {
        case .destinationUnavailable:
            HStack {
                Button("Check Again") { Task { await model.refreshHealth() } }
                Button("Choose Destination…") { actions.chooseDestination() }
            }
        case .photosAccessDenied:
            Button("Open Privacy Settings") { PhotosAccess.openPrivacySettings() }
        case .lastRunFailed:
            Button("Try Again") { model.startBackup() }
        case .backupStale:
            Button("Back Up Now") { model.startBackup() }
        }
    }
}

// MARK: - Tiles

struct StatTile: View {
    /// Two rows of four on a standard window (UX spec §4).
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
