#if DEBUG
import AppKit
import NoNeedCloudCore
import SwiftUI

/// Sample models for SwiftUI previews and `SnapshotRenderer`. Debug builds only.
@MainActor
enum PreviewData {
    final class Store: PlanStore, @unchecked Sendable {
        var plans: [BackupPlan]
        var runs: [BackupRun]
        init(plans: [BackupPlan], runs: [BackupRun] = []) { self.plans = plans; self.runs = runs }
        func loadPlans() throws -> [BackupPlan] { plans }
        func savePlans(_ plans: [BackupPlan]) throws { self.plans = plans }
        func loadRuns() throws -> [BackupRun] { runs }
        func saveRuns(_ runs: [BackupRun]) throws { self.runs = runs }
    }

    /// Publishes one fixed progress value and then waits until cancelled.
    struct FrozenEngine: BackupEngine {
        var progress: BackupProgress
        func run(_ plan: BackupPlan) -> AsyncThrowingStream<BackupProgress, any Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(progress)
                let task = Task {
                    try? await Task.sleep(for: .seconds(3600))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    static func folder(_ path: String) -> FolderReference {
        FolderReference(bookmark: Data(path.utf8), displayPath: path)
    }

    nonisolated static let homeArchive = DestinationDetails(
        volumeName: "Home Archive", kind: .network, networkProtocol: "SMB",
        remountURL: "smb://home-archive.local/NoNeedCloud", freeBytes: 1_200_000_000_000, isWritable: true
    )

    static func plan(sources: Bool = true, destination: Bool = true) -> BackupPlan {
        BackupPlan(
            photos: PhotoSettings(isEnabled: sources),
            files: FolderSettings(
                isEnabled: sources,
                folders: sources ? [folder(NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")] : []
            ),
            destination: destination ? folder("/Volumes/Home Archive/NoNeedCloud") : nil,
            destinationDetails: destination ? homeArchive : nil,
            schedule: ScheduleSettings(frequency: .daily, timeOfDayMinutes: 23 * 60)
        )
    }

    static func runs(for plan: BackupPlan, lastFinished: Date) -> [BackupRun] {
        let first = Calendar.current.date(byAdding: .month, value: -2, to: lastFinished)!
        return [
            BackupRun(planID: plan.id, startedAt: first.addingTimeInterval(-7200), finishedAt: first, outcome: .succeeded,
                      protectedPhotos: 22_410, protectedFiles: 2_980, copiedItems: 25_390, bytesWritten: 171_000_000_000),
            BackupRun(planID: plan.id, startedAt: lastFinished.addingTimeInterval(-900), finishedAt: lastFinished, outcome: .succeeded,
                      protectedPhotos: 24_860, protectedFiles: 3_214, copiedItems: 2_684, bytesWritten: 15_000_000_000),
        ]
    }

    /// The five runs from the Figma history frame.
    static func historyRuns(for plan: BackupPlan) -> [BackupRun] {
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: cal.date(bySettingHour: h, minute: m, second: 0, of: .now)!)!
        }
        let missed = [
            MissedItem(name: "IMG_2841.HEIC", location: "iCloud Photos", reason: "The iCloud download stopped partway."),
            MissedItem(name: "Family archive.mov", location: "iCloud Photos", reason: "Writing to the destination was interrupted."),
            MissedItem(name: "Old contract.pdf", location: "iCloud Drive / Documents", reason: "Permission is needed to read this file."),
        ]
        return [
            BackupRun(planID: plan.id, startedAt: at(2, 23, 2), finishedAt: at(2, 23, 20), outcome: .succeeded, trigger: .scheduled,
                      protectedPhotos: 24_100, protectedFiles: 3_150, processedItems: 27_250, copiedItems: 310, bytesWritten: 4_000_000_000),
            BackupRun(planID: plan.id, startedAt: at(1, 16, 44), finishedAt: at(1, 16, 52), outcome: .cancelled,
                      protectedPhotos: 24_100, protectedFiles: 3_150, processedItems: 9_000, copiedItems: 120, bytesWritten: 900_000_000),
            BackupRun(planID: plan.id, startedAt: at(1, 22, 51), finishedAt: at(1, 23, 5), outcome: .succeeded, trigger: .scheduled,
                      protectedPhotos: 24_500, protectedFiles: 3_190, processedItems: 27_380, copiedItems: 402, bytesWritten: 6_000_000_000),
            BackupRun(planID: plan.id, startedAt: at(0, 9, 18), finishedAt: at(0, 9, 30), outcome: .succeeded,
                      protectedPhotos: 24_700, protectedFiles: 3_200, processedItems: 27_420, copiedItems: 96, bytesWritten: 1_200_000_000),
            BackupRun(planID: plan.id, startedAt: at(0, 9, 41), finishedAt: at(0, 10, 16), outcome: .completedWithErrors,
                      protectedPhotos: 24_860, protectedFiles: 3_214, processedItems: 27_462, copiedItems: 2_498, failedItems: 3,
                      bytesWritten: 33_000_000_000, missedItems: missed),
        ]
    }

    static func model(_ state: String) -> AppModel {
        let today918 = Calendar.current.date(bySettingHour: 9, minute: 18, second: 0, of: .now)!
        switch state {
        case "setup1":
            return AppModel(store: Store(plans: [plan(sources: false, destination: false)]), engine: SimulatedBackupEngine())
        case "setup2", "setup3":
            return AppModel(store: Store(plans: [plan()]), engine: SimulatedBackupEngine(),
                            healthCheck: { _ in HealthSnapshot(photosAccessGranted: true, destination: homeArchive) })
        case "attention":
            let plan = plan()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.date(bySettingHour: 22, minute: 51, second: 0, of: .now)!)!
            return AppModel(store: Store(plans: [plan], runs: runs(for: plan, lastFinished: yesterday)), engine: SimulatedBackupEngine(),
                            healthCheck: { _ in HealthSnapshot(destinationAvailable: false) })
        case "running":
            let plan = plan()
            let progress = BackupProgress(
                phase: .copying, totalItems: 27_462, processedItems: 15_928, copiedItems: 2_481, failedItems: 0,
                processedPhotos: 13_000, processedFiles: 2_928, bytesWritten: 33_000_000_000,
                currentItem: .init(displayPath: "Photos/2026/11/22/IMG_2841.HEIC", stage: .fetch, kind: .photo),
                startedAt: Date().addingTimeInterval(-19 * 60), estimatedRemaining: 14 * 60
            )
            return AppModel(store: Store(plans: [plan], runs: runs(for: plan, lastFinished: today918)), engine: FrozenEngine(progress: progress))
        case "history":
            let plan = plan()
            return AppModel(store: Store(plans: [plan], runs: historyRuns(for: plan)), engine: SimulatedBackupEngine())
        default: // protected
            let plan = plan()
            return AppModel(store: Store(plans: [plan], runs: runs(for: plan, lastFinished: today918)), engine: SimulatedBackupEngine())
        }
    }
}

/// Renders each main-window screen offscreen to PNGs, then quits.
/// Run the debug app with `NNC_SNAPSHOT_DIR=<folder>` (inside the sandbox container).
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["NNC_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            let outDir = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            for state in ["launch", "welcome", "setup1", "setup2", "setup3", "protected", "running", "attention", "history"] {
                let model = PreviewData.model(state)
                await model.refreshHealth()
                if state == "running" {
                    model.startBackup()
                    try? await Task.sleep(for: .milliseconds(300))
                }
                let size = state == "history" ? CGSize(width: 1120, height: 648) : CGSize(width: 1000, height: 588)
                let root = SnapshotScreen(model: model, state: state)
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: root)
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: outDir.appendingPathComponent("\(state).png"))
                }
                model.stopBackup()
            }
            NSApp.terminate(nil)
        }
    }
}

/// Window content without the toolbar, as each screen appears below it.
private struct SnapshotScreen: View {
    let model: AppModel
    let state: String

    var body: some View {
        let actions = SetupActions(model: model, showSheet: { _ in })
        Group {
            if state == "history" {
                HistoryView(model: model)
            } else if state == "launch" {
                LaunchView()
            } else if state == "welcome" {
                WelcomeView {}
            } else {
                Group {
                    switch model.screenState {
                    case let .setup(reached):
                        SetupFlowView(model: model, reached: reached, actions: actions,
                                      initialStep: state == "setup2" ? .destination : nil)
                            .padding(.horizontal, -4)
                    case .running:
                        if let progress = model.progress { RunningView(model: model, progress: progress) }
                    case .protected:
                        ProtectedView(model: model, actions: actions)
                    case let .needsAttention(issue):
                        AttentionView(model: model, issue: issue, actions: actions)
                    }
                }
                .padding(.horizontal, 27)
                .padding(.top, 23)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.window)
            }
        }
        .environment(\.colorScheme, .light)
        .environment(AppRouter())
        // A snapshot is one frame: render entrance animations at their end state.
        .transaction { $0.animation = nil }
    }
}

#Preview("Launch") { LaunchView().frame(width: 1000, height: 588) }
#Preview("Welcome") { WelcomeView {}.frame(width: 1000, height: 588) }
#Preview("Setup · Sources") { MainWindowView(model: PreviewData.model("setup1"), startingAt: .app).frame(width: 1000, height: 650).environment(AppRouter()) }
#Preview("Setup · Destination") { MainWindowView(model: PreviewData.model("setup2"), startingAt: .app).frame(width: 1000, height: 650).environment(AppRouter()) }
#Preview("Protected") { MainWindowView(model: PreviewData.model("protected"), startingAt: .app).frame(width: 1000, height: 650).environment(AppRouter()) }
#Preview("History") { HistoryView(model: PreviewData.model("history")).frame(width: 1120, height: 650).environment(AppRouter()) }
#Preview("Needs attention") { MainWindowView(model: PreviewData.model("attention"), startingAt: .app).frame(width: 1000, height: 650).environment(AppRouter()) }
#endif
