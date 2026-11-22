import NoNeedCloudCore
import SwiftUI

/// Run history. Per-run detail and the missed-items list grow here in M3.
struct HistoryView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.planRuns.isEmpty {
                ContentUnavailableView(
                    "No backups yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Runs appear here after your first backup.")
                )
            } else {
                Table(model.planRuns) {
                    TableColumn("Started") { run in
                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .width(min: 140, ideal: 160)
                    TableColumn("Result") { run in
                        Label(title(run.outcome), systemImage: icon(run.outcome))
                            .foregroundStyle(color(run.outcome))
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Copied") { run in
                        Text(Formatting.count(run.copiedItems)).monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Missed") { run in
                        Text(Formatting.count(run.failedItems)).monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Duration") { run in
                        Text(Formatting.duration(run.duration)).monospacedDigit()
                    }
                    .width(70)
                }
            }
        }
        .navigationTitle("Backup History")
    }

    private func title(_ outcome: BackupRun.Outcome) -> String {
        switch outcome {
        case .succeeded: String(localized: "Completed")
        case .completedWithErrors: String(localized: "Completed, some missed")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Stopped")
        }
    }

    private func icon(_ outcome: BackupRun.Outcome) -> String {
        switch outcome {
        case .succeeded: "checkmark.circle.fill"
        case .completedWithErrors: "exclamationmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    private func color(_ outcome: BackupRun.Outcome) -> Color {
        switch outcome {
        case .succeeded: .green
        case .completedWithErrors: .orange
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
