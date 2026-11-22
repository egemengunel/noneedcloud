import Foundation
import Observation

/// App-wide state: the current plan, run history, live progress and health.
/// The main window, menu bar extra and (later) App Intents all read this.
@MainActor
@Observable
public final class AppModel {
    public typealias HealthCheck = @Sendable (BackupPlan) async -> HealthSnapshot

    @ObservationIgnored private let store: any PlanStore
    @ObservationIgnored private let engine: any BackupEngine
    @ObservationIgnored private let healthCheck: HealthCheck
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let minimumUpdateInterval: TimeInterval
    @ObservationIgnored private var runTask: Task<Void, Never>?

    /// The plan the main window edits. Multiple plans arrive with M6.
    public private(set) var plan: BackupPlan
    public private(set) var runs: [BackupRun]
    public private(set) var progress: BackupProgress?
    public private(set) var isRunning = false
    public private(set) var health = HealthSnapshot()
    /// Last persistence error, for a non-blocking message in the UI.
    public private(set) var saveError: String?

    public init(
        store: any PlanStore,
        engine: any BackupEngine,
        healthCheck: @escaping HealthCheck = { _ in HealthSnapshot() },
        now: @escaping @Sendable () -> Date = Date.init,
        minimumUpdateInterval: TimeInterval = 0.2
    ) {
        self.store = store
        self.engine = engine
        self.healthCheck = healthCheck
        self.now = now
        self.minimumUpdateInterval = minimumUpdateInterval
        plan = (try? store.loadPlans())?.first ?? BackupPlan()
        runs = (try? store.loadRuns()) ?? []
    }

    // MARK: - Derived state

    public var screenState: MainScreenState {
        MainScreenState.derive(plan: plan, runs: runs, isRunning: isRunning, health: health, now: now())
    }

    public var planRuns: [BackupRun] {
        runs.filter { $0.planID == plan.id }.sorted { $0.startedAt > $1.startedAt }
    }

    public var lastRun: BackupRun? { planRuns.first }
    public var lastCompletedRun: BackupRun? { planRuns.first(where: \.didComplete) }
    public var firstCompletedRun: BackupRun? { planRuns.last(where: \.didComplete) }

    public var protectedPhotos: Int { lastCompletedRun?.protectedPhotos ?? 0 }
    public var protectedFiles: Int { lastCompletedRun?.protectedFiles ?? 0 }
    public var protectedSince: Date? { firstCompletedRun?.finishedAt }

    /// Items protected now minus items protected after the first run.
    public var addedSinceFirstRun: Int {
        guard let first = firstCompletedRun, let last = lastCompletedRun else { return 0 }
        return max(0, (last.protectedPhotos + last.protectedFiles) - (first.protectedPhotos + first.protectedFiles))
    }

    public var totalBytesWritten: Int64 { planRuns.reduce(0) { $0 + $1.bytesWritten } }

    // MARK: - Editing the plan

    public func updatePlan(_ change: (inout BackupPlan) -> Void) {
        var updated = plan
        change(&updated)
        guard updated != plan else { return }
        plan = updated
        persistPlan()
    }

    public func addFolders(_ folders: [FolderReference]) {
        updatePlan { plan in
            for folder in folders where !plan.files.folders.contains(where: { $0.displayPath == folder.displayPath }) {
                plan.files.folders.append(folder)
            }
            if !plan.files.folders.isEmpty { plan.files.isEnabled = true }
        }
    }

    public func removeFolder(_ folder: FolderReference) {
        updatePlan { $0.files.folders.removeAll { $0.displayPath == folder.displayPath } }
    }

    public func removeAllFolders() {
        updatePlan { $0.files.folders.removeAll() }
    }

    public func setDestination(_ destination: FolderReference?) {
        updatePlan { $0.destination = destination }
        Task { await refreshHealth() }
    }

    public func refreshHealth() async {
        let snapshot = await healthCheck(plan)
        if snapshot != health { health = snapshot }
    }

    // MARK: - Running

    public var canStartBackup: Bool {
        guard plan.isReadyToRun, !isRunning else { return false }
        if case .needsAttention(.destinationUnavailable) = screenState { return false }
        return true
    }

    public func startBackup() {
        guard canStartBackup else { return }
        let plan = self.plan
        let startedAt = now()
        isRunning = true
        progress = BackupProgress(startedAt: startedAt)

        runTask = Task { [weak self] in
            guard let self else { return }
            var latest = BackupProgress(startedAt: startedAt)
            var lastApplied = Date.distantPast
            var outcome: BackupRun.Outcome = .cancelled
            var failureReason: String?
            do {
                for try await update in engine.run(plan) {
                    latest = update
                    let time = now()
                    if update.phase != progress?.phase || time.timeIntervalSince(lastApplied) >= minimumUpdateInterval {
                        progress = update
                        lastApplied = time
                    }
                }
                if Task.isCancelled || latest.phase != .finished {
                    outcome = .cancelled
                } else {
                    outcome = latest.failedItems > 0 ? .completedWithErrors : .succeeded
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = Task.isCancelled ? .cancelled : .failed
                failureReason = Task.isCancelled ? nil : error.localizedDescription
            }
            finishRun(plan: plan, progress: latest, outcome: outcome, failureReason: failureReason)
        }
    }

    public func stopBackup() {
        runTask?.cancel()
    }

    /// Waits for the current run (if any) to finish. For tests and App Intents.
    public func waitForCurrentRun() async {
        await runTask?.value
    }

    private func finishRun(plan: BackupPlan, progress: BackupProgress, outcome: BackupRun.Outcome, failureReason: String?) {
        let previous = lastCompletedRun
        let completed = outcome == .succeeded || outcome == .completedWithErrors
        let run = BackupRun(
            planID: plan.id,
            startedAt: progress.startedAt,
            finishedAt: now(),
            outcome: outcome,
            failureReason: failureReason,
            // An interrupted run only proves what it reached; keep the larger known total.
            protectedPhotos: completed ? progress.processedPhotos : max(progress.processedPhotos, previous?.protectedPhotos ?? 0),
            protectedFiles: completed ? progress.processedFiles : max(progress.processedFiles, previous?.protectedFiles ?? 0),
            copiedItems: progress.copiedItems,
            failedItems: progress.failedItems,
            bytesWritten: progress.bytesWritten
        )
        runs.append(run)
        self.progress = nil
        isRunning = false
        runTask = nil
        do {
            try store.saveRuns(runs)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func persistPlan() {
        do {
            try store.savePlans([plan])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
