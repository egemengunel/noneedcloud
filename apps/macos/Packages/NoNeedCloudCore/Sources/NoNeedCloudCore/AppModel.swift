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
    /// Shows the newest throttled update once the engine goes quiet.
    @ObservationIgnored private var trailingUpdate: Task<Void, Never>?
    @ObservationIgnored private let loginItem: LoginItemControl?
    /// Anchor for the first scheduled run when the plan has never run.
    @ObservationIgnored private let launchedAt: Date

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
        minimumUpdateInterval: TimeInterval = 0.2,
        loginItem: LoginItemControl? = nil
    ) {
        self.store = store
        self.engine = engine
        self.healthCheck = healthCheck
        self.now = now
        self.minimumUpdateInterval = minimumUpdateInterval
        self.loginItem = loginItem
        self.launchedAt = now()
        plan = (try? store.loadPlans())?.first ?? BackupPlan()
        runs = (try? store.loadRuns()) ?? []
        // The login item can be removed in System Settings; reflect that.
        if let loginItem, loginItem.isEnabled() != plan.schedule.startAtLogin {
            plan.schedule.startAtLogin = loginItem.isEnabled()
        }
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
        let wantsLoginItem = updated.schedule.startAtLogin
        var loginItemError: String?
        if let loginItem, wantsLoginItem != plan.schedule.startAtLogin {
            do {
                try loginItem.setEnabled(wantsLoginItem)
            } catch {
                loginItemError = error.localizedDescription
            }
            updated.schedule.startAtLogin = loginItem.isEnabled()
        }
        if updated != plan {
            plan = updated
            persistPlan()
        }
        if let loginItemError { saveError = loginItemError }
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
        updatePlan {
            $0.destination = destination
            $0.destinationDetails = nil
        }
        Task { await refreshHealth() }
    }

    public func refreshHealth() async {
        let snapshot = await healthCheck(plan)
        if snapshot != health { health = snapshot }
        // Remember the volume details so they're still shown when it's unplugged.
        if let details = snapshot.destination, details != plan.destinationDetails {
            updatePlan { $0.destinationDetails = details }
        }
    }

    /// When the next scheduled backup is due, or nil for manual backups.
    public var nextScheduledRun: Date? {
        plan.schedule.nextRun(after: now())
    }

    /// Bytes copied across all completed runs: an estimate of the archive size.
    public var archiveBytes: Int64 {
        planRuns.filter(\.didComplete).reduce(0) { $0 + $1.bytesWritten }
    }

    /// When the next scheduled run is due. Unlike `nextScheduledRun` this is
    /// anchored to the last run, so a time the Mac slept through stays due
    /// (and runs once on wake) instead of being skipped.
    public var scheduledRunDue: Date? {
        let anchor = planRuns.first?.startedAt ?? launchedAt
        return plan.schedule.nextRun(after: anchor)
    }

    /// Starts a scheduled backup if one is due. Called by the app's ticker
    /// every minute and when the Mac wakes.
    @discardableResult
    public func runScheduledBackupIfDue() -> Bool {
        guard let due = scheduledRunDue, now() >= due, canStartBackup else { return false }
        startBackup(trigger: .scheduled)
        return true
    }

    // MARK: - Running

    public var canStartBackup: Bool {
        guard plan.isReadyToRun, !isRunning else { return false }
        if case .needsAttention(.destinationUnavailable) = screenState { return false }
        return true
    }

    public func startBackup(trigger: BackupRun.Trigger = .manual) {
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
                    let wait = minimumUpdateInterval - time.timeIntervalSince(lastApplied)
                    trailingUpdate?.cancel()
                    trailingUpdate = nil
                    if update.phase != progress?.phase || wait <= 0 {
                        progress = update
                        lastApplied = time
                    } else {
                        trailingUpdate = Task { [weak self] in
                            try? await Task.sleep(for: .seconds(wait))
                            guard !Task.isCancelled, let self, self.isRunning else { return }
                            self.progress = update
                        }
                    }
                }
                trailingUpdate?.cancel()
                trailingUpdate = nil
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
            finishRun(plan: plan, startedAt: startedAt, progress: latest, outcome: outcome, trigger: trigger, failureReason: failureReason)
        }
    }

    public func stopBackup() {
        runTask?.cancel()
    }

    /// Waits for the current run (if any) to finish. For tests and App Intents.
    public func waitForCurrentRun() async {
        await runTask?.value
    }

    private func finishRun(
        plan: BackupPlan,
        startedAt: Date,
        progress: BackupProgress,
        outcome: BackupRun.Outcome,
        trigger: BackupRun.Trigger,
        failureReason: String?
    ) {
        let previous = lastCompletedRun
        let completed = outcome == .succeeded || outcome == .completedWithErrors
        let run = BackupRun(
            planID: plan.id,
            startedAt: startedAt,
            finishedAt: now(),
            outcome: outcome,
            trigger: trigger,
            failureReason: failureReason,
            // An interrupted run only proves what it reached; keep the larger known total.
            protectedPhotos: completed ? progress.processedPhotos : max(progress.processedPhotos, previous?.protectedPhotos ?? 0),
            protectedFiles: completed ? progress.processedFiles : max(progress.processedFiles, previous?.protectedFiles ?? 0),
            processedItems: progress.processedItems,
            copiedItems: progress.copiedItems,
            failedItems: progress.failedItems,
            bytesWritten: progress.bytesWritten,
            missedItems: progress.missedItems
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
