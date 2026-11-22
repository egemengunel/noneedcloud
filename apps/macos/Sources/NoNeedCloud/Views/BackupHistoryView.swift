import SwiftUI

struct BackupHistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView(
                    "No Backup History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Runs will appear here after your first backup.")
                )
            } else {
                List {
                    ForEach(model.history.reversed()) { record in
                        NavigationLink {
                            BackupRunDetailView(record: record)
                        } label: {
                            BackupRunRow(record: record, planName: model.planName(for: record.planId))
                        }
                    }
                }
            }
        }
        .navigationTitle("Backup History")
    }
}

struct BackupRunRow: View {
    let record: BackupRunRecord
    let planName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                OutcomeBadge(outcome: record.outcome)
                Text(planName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.end.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                LabeledContent("Duration") { Text(durationText) }
                LabeledContent("Copied") { Text("\(record.itemsCopied)") }
                LabeledContent("Skipped") { Text("\(record.itemsSkipped)") }
                if record.itemsFailed > 0 {
                    LabeledContent("Failed") {
                        Text("\(record.itemsFailed)")
                            .foregroundStyle(.red)
                    }
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var durationText: String {
        Duration.seconds(record.end.timeIntervalSince(record.start))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

struct BackupRunDetailView: View {
    let record: BackupRunRecord

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Outcome") { OutcomeBadge(outcome: record.outcome) }
                LabeledContent("Started") { Text(record.start.formatted(date: .abbreviated, time: .standard)) }
                LabeledContent("Ended") { Text(record.end.formatted(date: .abbreviated, time: .standard)) }
                LabeledContent("Copied") { Text("\(record.itemsCopied)") }
                LabeledContent("Skipped") { Text("\(record.itemsSkipped)") }
                LabeledContent("Failed") { Text("\(record.itemsFailed)") }
                LabeledContent("Bytes") { Text(record.bytesCopied.formatted(.byteCount(style: .memory))) }
            }
            Section("Item Errors") {
                if record.errors.isEmpty {
                    Text("No per-item errors in this run.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(record.errors.enumerated()), id: \.offset) { _, error in
                        BackupFileErrorRow(error: error)
                    }
                }
            }
        }
        .navigationTitle("Run Details")
    }
}

struct BackupFileErrorRow: View {
    let error: BackupFileError

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(error.path)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.head)
                .textSelection(.enabled)
            Text(error.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

struct OutcomeBadge: View {
    let outcome: CopyRunResult.Outcome

    var body: some View {
        Text(label)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch outcome {
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }

    private var color: Color {
        switch outcome {
        case .completed: .green
        case .cancelled: .orange
        case .failed: .red
        }
    }
}

struct LastRunCard: View {
    let record: BackupRunRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Run")
                .font(.headline)
            if let record {
                HStack {
                    OutcomeBadge(outcome: record.outcome)
                    Spacer()
                    Text(record.end.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    LabeledContent("Copied") { Text("\(record.itemsCopied)") }
                    LabeledContent("Skipped") { Text("\(record.itemsSkipped)") }
                    if record.itemsFailed > 0 {
                        LabeledContent("Failed") {
                            Text("\(record.itemsFailed)")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .font(.callout)
                .monospacedDigit()
            } else {
                Text("No runs yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
