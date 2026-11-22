import SwiftUI

struct AtAGlanceView: View {
    @ObservedObject var model: AppModel
    @State private var selectedPlanId: UUID?
    @State private var editorTarget: PlanEditorTarget?
    @State private var planPendingDelete: BackupPlan?

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
                            value: "\(selectedPlanProtectedCount)",
                            detail: selectedPlanLastRecord == nil ? "Nothing backed up yet" : "In \(selectedPlan?.name ?? "your plan")'s latest run"
                        )
                        StatTile(
                            title: "Last Backup",
                            value: selectedPlanLastBackupText,
                            detail: selectedPlanLastRunDetail
                        )
                    }

                    LastRunCard(record: selectedPlanLastRecord)

                    progressOrStart

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Missed Items")
                            .font(.headline)
                        MissedItemsView(items: selectedPlanMissedItems)
                    }

                    plansSection

                    loginItemSection

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
            .sheet(item: $editorTarget) { target in
                PlanEditorView(model: model, plan: target.plan)
            }
            .alert(
                "Delete Plan",
                isPresented: Binding(
                    get: { planPendingDelete != nil },
                    set: { if !$0 { planPendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Delete \"\(planPendingDelete?.name ?? "")\"? Its backup history is kept.")
            }
        }
    }

    private var selectedPlan: BackupPlan? {
        model.plans.first { $0.id == selectedPlanId } ?? model.plans.first
    }

    private var selectedPlanLastRecord: BackupRunRecord? {
        guard let plan = selectedPlan else { return nil }
        return model.history.last { $0.planId == plan.id }
    }

    private var selectedPlanProtectedCount: Int {
        guard let record = selectedPlanLastRecord else { return 0 }
        return record.itemsCopied + record.itemsSkipped
    }

    private var selectedPlanLastBackupText: String {
        guard let record = selectedPlanLastRecord else { return "Never" }
        return record.end.formatted(date: .abbreviated, time: .shortened)
    }

    private var selectedPlanLastRunDetail: String {
        guard let record = selectedPlanLastRecord else { return "No backup has run" }
        return switch record.outcome {
        case .completed: "Completed successfully"
        case .cancelled: "Last run was stopped"
        case .failed: "Last run had errors"
        }
    }

    private var selectedPlanMissedItems: [BackupFileError] {
        guard let plan = selectedPlan else { return [] }
        return model.missedItems(for: plan.id)
    }

    @ViewBuilder
    private var progressOrStart: some View {
        if let engine = model.activeEngine {
            BackupProgressCard(state: engine.state, onStop: { model.stopBackup() })
        } else if let photoRunner = model.activePhotoRunner {
            BackupProgressCard(state: photoRunner.state, onStop: { model.stopBackup() })
        } else if let plan = selectedPlan {
            HStack(spacing: 16) {
                Picker("Plan", selection: Binding(
                    get: { selectedPlan?.id },
                    set: { selectedPlanId = $0 }
                )) {
                    ForEach(model.plans) { plan in
                        Text(plan.name).tag(plan.id)
                    }
                }
                .frame(maxWidth: 240)

                Button("Start Backup") { model.startBackup(plan) }
                    .controlSize(.large)
                    .disabled(model.isBackupRunning)
            }
        }
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Plans")
                    .font(.headline)
                Spacer()
                Button("Add Plan…") { editorTarget = PlanEditorTarget(plan: nil) }
            }
            if model.plans.isEmpty {
                Text("No backup plans yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.plans) { plan in
                    PlanSummaryCard(
                        plan: plan,
                        lastRecord: model.history.last { $0.planId == plan.id },
                        isRunning: model.isPlanRunning(plan.id),
                        isSelected: plan.id == selectedPlan?.id,
                        onEdit: { editorTarget = PlanEditorTarget(plan: plan) },
                        onDelete: { planPendingDelete = plan }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var loginItemSection: some View {
        if model.loginItem != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("General")
                    .font(.headline)
                Toggle(
                    "Start NoNeedCloud at Login",
                    isOn: Binding(
                        get: { model.startAtLogin },
                        set: { model.setStartAtLogin($0) }
                    )
                )
                if let error = model.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func confirmDelete() {
        guard let plan = planPendingDelete else { return }
        planPendingDelete = nil
        model.deletePlan(plan.id)
        if selectedPlanId == plan.id {
            selectedPlanId = nil
        }
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
    let lastRecord: BackupRunRecord?
    let isRunning: Bool
    let isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.name)
                    .font(.headline)
                if isSelected {
                    Text("Selected")
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit Plan")
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isRunning)
                .help(isRunning ? "Stop the backup before deleting this plan" : "Delete Plan")
            }
            LabeledContent("Sources") { Text(sourcesSummary) }
            LabeledContent("Destination") {
                Text(plan.destination.displayName)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            LabeledContent("Schedule") { Text(plan.schedule.summary) }
            LabeledContent("Last Run") { Text(lastRunSummary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
        )
    }

    private var sourcesSummary: String {
        var parts = plan.sources.map(\.displayName)
        if plan.includePhotos {
            parts.append("Photos")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " · ")
    }

    private var lastRunSummary: String {
        guard let lastRecord else { return "Never" }
        let outcome: String = switch lastRecord.outcome {
        case .completed: "Completed"
        case .cancelled: "Stopped"
        case .failed: "Failed"
        }
        return "\(lastRecord.end.formatted(date: .abbreviated, time: .shortened)) · \(outcome)"
    }
}
