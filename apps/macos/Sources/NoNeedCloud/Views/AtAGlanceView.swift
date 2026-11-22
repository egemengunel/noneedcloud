import AppKit
import SwiftUI

struct AtAGlanceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("At a Glance")
                    .font(.largeTitle)
                    .bold()

                HStack(spacing: 12) {
                    StatTile(
                        title: "Items Protected",
                        value: "0",
                        detail: "Nothing backed up yet"
                    )
                    StatTile(
                        title: "Last Backup",
                        value: "Never",
                        detail: "No backup has run"
                    )
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
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        var parts: [String] = []
        let count = plan.sourceFolderURLs.count
        if count > 0 {
            parts.append(count == 1 ? "1 folder" : "\(count) folders")
        }
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
