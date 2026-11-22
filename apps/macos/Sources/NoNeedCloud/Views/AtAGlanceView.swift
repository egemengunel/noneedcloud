import SwiftUI

struct AtAGlanceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("At a Glance")
                        .font(.largeTitle)
                        .bold()

                    HStack(spacing: 12) {
                        StatTile(
                            title: "Items Protected",
                            value: "\(model.itemsProtected)",
                            detail: model.itemsProtected > 0 ? "In your latest backup" : "Nothing backed up yet"
                        )
                        StatTile(
                            title: "Last Backup",
                            value: lastBackupText,
                            detail: model.lastBackupDate == nil ? "No backup has run" : "Completed successfully"
                        )
                    }

                    LastRunCard(record: model.history.last)

                    if let engine = model.activeEngine {
                        BackupProgressCard(state: engine.state, onStop: { model.stopBackup() })
                    } else if let photoRunner = model.activePhotoRunner {
                        BackupProgressCard(state: photoRunner.state, onStop: { model.stopBackup() })
                    } else if let plan = model.plans.first {
                        Button("Start Backup") { model.startBackup(plan) }
                            .controlSize(.large)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Missed Items")
                            .font(.headline)
                        MissedItemsView(items: missedItemsForPlans)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backup Plans")
                            .font(.headline)
                        if model.plans.isEmpty {
                            Text("No backup plans yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.plans) { plan in
                                PlanSummaryCard(plan: plan)
                            }
                        }
                    }

                    NavigationLink {
                        BackupHistoryView(model: model)
                    } label: {
                        HStack {
                            Text("Backup History")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var missedItemsForPlans: [BackupFileError] {
        guard let plan = model.plans.first else { return [] }
        return model.missedItems(for: plan.id)
    }

    private var lastBackupText: String {
        guard let lastBackupDate = model.lastBackupDate else { return "Never" }
        return lastBackupDate.formatted(date: .abbreviated, time: .shortened)
    }
}
struct BackupProgressCard: View {
    @ObservedObject var state: CopyEngineState
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Backup in Progress")
                    .font(.headline)
                Spacer()
                Button("Stop", role: .destructive, action: onStop)
                    .disabled(!state.isRunning)
            }

            ProgressView(value: state.percent) {
                Text(percentText)
                    .monospacedDigit()
            }

            if let currentFile = state.currentFile {
                Text(currentFile)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                LabeledContent("Copied") { Text("\(state.itemsCopied)") }
                LabeledContent("Skipped") { Text("\(state.itemsSkipped)") }
                LabeledContent("Total") { Text("\(state.itemsTotal)") }
            }
            .font(.callout)

            HStack(spacing: 16) {
                LabeledContent("Bytes") { Text(state.bytesCopied.formatted(.byteCount(style: .memory))) }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LabeledContent("Elapsed") { Text(elapsedText) }
                }
                LabeledContent("Started") {
                    Text(state.startedAt?.formatted(date: .omitted, time: .standard) ?? "—")
                }
            }
            .font(.callout)

            if !state.errors.isEmpty {
                Text("\(state.errors.count) item(s) skipped due to errors.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var percentText: String {
        "\(Int((state.percent * 100).rounded()))%"
    }

    private var elapsedText: String {
        Duration.seconds(state.elapsed)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .bold()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PlanSummaryCard: View {
    let plan: BackupPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.name)
                .font(.headline)
            LabeledContent("Sources") { Text(sourcesSummary) }
            LabeledContent("Destination") {
                Text(plan.destinationURL.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            LabeledContent("Schedule") { Text(scheduleSummary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sourcesSummary: String {
        var parts = plan.sources.map(\.displayName)
        if plan.includePhotos {
            parts.append("Photos")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private var scheduleSummary: String {
        switch plan.schedule {
        case .manual: "Manual"
        }
    }
}
