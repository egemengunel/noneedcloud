import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: any PlanStore
    let historyStore: any RunHistoryStore
    let runStateDirectory: URL
    let photoSourceFactory: @Sendable () -> any PhotoLibrarySource

    @Published private(set) var plans: [BackupPlan]
    @Published private(set) var isSetupCompleted: Bool
    @Published private(set) var isBackupRunning = false
    @Published private(set) var activeEngine: CopyEngine?
    @Published private(set) var activePhotoRunner: PhotoBackupCoordinator?
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var itemsProtected = 0
    @Published private(set) var history: [BackupRunRecord]

    init(
        store: any PlanStore,
        runStateDirectory: URL? = nil,
        historyStore: (any RunHistoryStore)? = nil,
        photoSourceFactory: @escaping @Sendable () -> any PhotoLibrarySource = { PhotosFrameworkSource() }
    ) {
        self.store = store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runStateDirectory = runStateDirectory
            ?? appSupport.appendingPathComponent("NoNeedCloud/RunState", isDirectory: true)
        self.historyStore = historyStore ?? JSONRunHistoryStore(directory: self.runStateDirectory)
        self.photoSourceFactory = photoSourceFactory
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
        history = (try? self.historyStore.loadRecords()) ?? []
    }

    var isSetupNeeded: Bool {
        plans.isEmpty && !isSetupCompleted
    }

    func finishSetup(_ plan: BackupPlan) {
        plans.append(plan)
        isSetupCompleted = true
        try? store.savePlans(plans)
        try? store.setSetupCompleted(true)
    }

    func startBackup(_ plan: BackupPlan) {
        guard !isBackupRunning, !plan.sources.isEmpty || plan.includePhotos else { return }
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
        guard !isBackupRunning else { return [] }
        isBackupRunning = true
        defer {
            isBackupRunning = false
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
                stateURL: IncrementalIndex.indexFileURL(stateDirectory: runStateDirectory, source: source),
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
