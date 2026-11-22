import AppKit
import SwiftUI

struct MenuBarPlanRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let lastRunLabel: String
    let isRunning: Bool
}

enum MenuBarViewModel {
    static let idleIconName = "arrow.down.circle"
    static let runningIconName = "arrow.down.circle.fill"

    static func icon(isBackupRunning: Bool) -> String {
        isBackupRunning ? runningIconName : idleIconName
    }

    static func lastRunLabel(lastRun: Date?) -> String {
        lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    static func planRows(
        plans: [BackupPlan],
        runningPlanIds: Set<UUID>,
        lastRun: (UUID) -> Date?
    ) -> [MenuBarPlanRow] {
        plans
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { plan in
                MenuBarPlanRow(
                    id: plan.id,
                    name: plan.name,
                    lastRunLabel: lastRunLabel(lastRun: lastRun(plan.id)),
                    isRunning: runningPlanIds.contains(plan.id)
                )
            }
    }
}

struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: MenuBarViewModel.icon(isBackupRunning: model.isBackupRunning))
            .accessibilityLabel("NoNeedCloud")
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progressSection
            Divider()
            planRowsSection
            Divider()
            Button("Open NoNeedCloud") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let runningPlanName {
            Text("Backing up: \(runningPlanName)")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        if let engine = model.activeEngine {
            BackupProgressCard(state: engine.state, onStop: { model.stopBackup() })
        } else if let photoRunner = model.activePhotoRunner {
            BackupProgressCard(state: photoRunner.state, onStop: { model.stopBackup() })
        } else {
            Text("No backup running")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var planRowsSection: some View {
        if model.plans.isEmpty {
            Text("No backup plans yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(planRows) { row in
                startButton(row: row)
            }
        }
    }

    private var runningPlanName: String? {
        model.plans.first { model.isPlanRunning($0.id) }?.name
    }

    private var planRows: [MenuBarPlanRow] {
        MenuBarViewModel.planRows(
            plans: model.plans,
            runningPlanIds: model.runningPlanIds
        ) { model.lastRunDate(for: $0) }
    }

    private func startButton(row: MenuBarPlanRow) -> some View {
        Button {
            if let plan = model.plans.first(where: { $0.id == row.id }) {
                model.startBackup(plan)
            }
        } label: {
            HStack {
                Text(row.name)
                if row.isRunning {
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Text(row.lastRunLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isBackupRunning)
    }
}
