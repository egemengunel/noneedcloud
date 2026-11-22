import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: any PlanStore
    let historyStore: any RunHistoryStore
    let runStateDirectory: URL
    let photoSourceFactory: @Sendable () -> any PhotoLibrarySource
    let loginItem: (any LoginItemService)?

    @Published private(set) var plans: [BackupPlan]
    @Published private(set) var isSetupCompleted: Bool
    @Published private(set) var isBackupRunning = false
    @Published private(set) var runningPlanIds: Set<UUID> = []
    @Published private(set) var activeEngine: CopyEngine?
    @Published private(set) var activePhotoRunner: PhotoBackupCoordinator?
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var itemsProtected = 0
    @Published private(set) var history: [BackupRunRecord]
    @Published private(set) var startAtLogin = false
    @Published private(set) var loginItemError: String?

    init(
        store: any PlanStore,
        runStateDirectory: URL? = nil,
        historyStore: (any RunHistoryStore)? = nil,
        photoSourceFactory: @escaping @Sendable () -> any PhotoLibrarySource = { PhotosFrameworkSource() },
        loginItem: (any LoginItemService)? = nil
    ) {
        self.store = store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runStateDirectory = runStateDirectory
            ?? appSupport.appendingPathComponent("NoNeedCloud/RunState", isDirectory: true)
        self.historyStore = historyStore ?? JSONRunHistoryStore(directory: self.runStateDirectory)
        self.photoSourceFactory = photoSourceFactory
        self.loginItem = loginItem
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
        history = (try? self.historyStore.loadRecords()) ?? []
        startAtLogin = loginItem?.isEnabled() ?? false
    }

    var isSetupNeeded: Bool {
        plans.isEmpty && !isSetupCompleted
    }

    func finishSetup(_ plan: BackupPlan) {
        addPlan(plan)
        isSetupCompleted = true
        try? store.setSetupCompleted(true)
    }

    func addPlan(_ plan: BackupPlan) {
        plans.append(plan)
        try? store.savePlans(plans)
    }

    func updatePlan(_ plan: BackupPlan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        try? store.savePlans(plans)
    }

    func deletePlan(_ planId: UUID) {
        plans.removeAll { $0.id == planId }
        try? store.savePlans(plans)
    }

    func planName(for planId: UUID) -> String {
        plans.first { $0.id == planId }?.name ?? "Deleted plan"
    }

    func isPlanRunning(_ planId: UUID) -> Bool {
        runningPlanIds.contains(planId)
    }

    func lastRunDate(for planId: UUID) -> Date? {
        history.last(where: { $0.planId == planId })?.end
    }

    func setStartAtLogin(_ enabled: Bool) {
        guard let loginItem else { return }
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        startAtLogin = loginItem.isEnabled()
    }

    func startBackup(_ plan: BackupPlan) {
        guard !isBackupRunning, !runningPlanIds.contains(plan.id), !plan.sources.isEmpty || plan.includePhotos else { return }
        runningPlanIds.insert(plan.id)
        Task(priority: .background) { await backup(plan) }
    }

    func stopBackup() {
        activeEngine?.stop()
        activePhotoRunner?.stop()
    }

    func missedItems(for planId: UUID) -> [BackupFileError] {
        history.last(where: { $0.planId == planId })?.errors ?? []
    }

    @discardableResult
    func backup(_ plan: BackupPlan) async -> [CopyRunResult] {
        guard !isBackupRunning else {
            runningPlanIds.remove(plan.id)
            return []
        }
        isBackupRunning = true
        runningPlanIds.insert(plan.id)
        defer {
            isBackupRunning = false
            runningPlanIds.remove(plan.id)
            activeEngine = nil
            activePhotoRunner = nil
        }
        let runStart = Date()
        var results: [CopyRunResult] = []
        var runErrors: [BackupFileError] = []
        var protectedTotal = 0
        for source in plan.sources {
            let ubiquitousSource: (any UbiquitousFileSource)? = switch source {
            case .folder: nil
            case .icloudDrive, .appContainer: ICloudDriveSource()
            }
            let engine = CopyEngine(
                sourceURL: source.sourceURL,
                destinationURL: plan.destinationURL.appendingPathComponent(
                    source.displayName,
                    isDirectory: true
                ),
                stateURL: IncrementalIndex.indexFileURL(
                    stateDirectory: runStateDirectory,
                    destination: plan.destinationURL,
                    source: source
                ),
                ubiquitousSource: ubiquitousSource
            )
            activeEngine = engine
            let result = await engine.run()
            results.append(result)
            runErrors += engine.state.errors
            protectedTotal += result.itemsProtected
            if result.outcome == .cancelled { break }
        }
        activeEngine = nil
        if plan.includePhotos, !results.contains(where: { $0.outcome == .cancelled }) {
            let photoRunner = PhotoBackupCoordinator(
                source: photoSourceFactory(),
                destinationURL: plan.destinationURL,
                options: plan.photoOptions,
                stateURL: PhotoIncrementalIndex.indexFileURL(
                    stateDirectory: runStateDirectory,
                    destination: plan.destinationURL
                )
            )
            activePhotoRunner = photoRunner
            let photoResult = await photoRunner.run()
            activePhotoRunner = nil
            results.append(photoResult)
            runErrors += photoRunner.state.errors
            protectedTotal += photoResult.itemsProtected
        }
        itemsProtected = protectedTotal
        if !results.isEmpty, results.allSatisfy({ $0.outcome == .completed }) {
            lastBackupDate = Date()
        }
        appendHistoryRecord(plan: plan, start: runStart, end: Date(), results: results, errors: runErrors)
        return results
    }

    private func appendHistoryRecord(
        plan: BackupPlan,
        start: Date,
        end: Date,
        results: [CopyRunResult],
        errors: [BackupFileError]
    ) {
        guard !results.isEmpty else { return }
        let outcome: CopyRunResult.Outcome = if results.contains(where: { $0.outcome == .cancelled }) {
            .cancelled
        } else if results.contains(where: { $0.outcome == .failed }) {
            .failed
        } else {
            .completed
        }
        let record = BackupRunRecord(
            planId: plan.id,
            start: start,
            end: end,
            outcome: outcome,
            itemsCopied: results.reduce(0) { $0 + $1.itemsCopied },
            itemsSkipped: results.reduce(0) { $0 + $1.itemsSkipped },
            itemsFailed: results.reduce(0) { $0 + $1.itemsFailed },
            bytesCopied: results.reduce(0) { $0 + $1.bytesCopied },
            errors: errors
        )
        history.append(record)
        try? historyStore.append(record)
    }
}

extension AppModel: PlanScheduling {}
