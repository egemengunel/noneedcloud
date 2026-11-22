import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: any PlanStore
    let historyStore: any RunHistoryStore
    let runStateDirectory: URL

    @Published private(set) var plans: [BackupPlan]
    @Published private(set) var isSetupCompleted: Bool
    @Published private(set) var activeEngine: CopyEngine?
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var itemsProtected = 0
    @Published private(set) var history: [BackupRunRecord]

    init(store: any PlanStore, runStateDirectory: URL? = nil, historyStore: (any RunHistoryStore)? = nil) {
        self.store = store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runStateDirectory = runStateDirectory
            ?? appSupport.appendingPathComponent("NoNeedCloud/RunState", isDirectory: true)
        self.historyStore = historyStore ?? JSONRunHistoryStore(directory: self.runStateDirectory)
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
        history = (try? self.historyStore.loadRecords()) ?? []
    }

    var isSetupNeeded: Bool {
        plans.isEmpty && !isSetupCompleted
    }

    var isBackupRunning: Bool {
        activeEngine != nil
    }

    func finishSetup(_ plan: BackupPlan) {
        plans.append(plan)
        isSetupCompleted = true
        try? store.savePlans(plans)
        try? store.setSetupCompleted(true)
    }

    func startBackup(_ plan: BackupPlan) {
        guard !isBackupRunning, !plan.sourceFolderURLs.isEmpty else { return }
        Task(priority: .background) { await backup(plan) }
    }

    func stopBackup() {
        activeEngine?.stop()
    }

    func missedItems(for planId: UUID) -> [BackupFileError] {
        history.last(where: { $0.planId == planId })?.errors ?? []
    }

    @discardableResult
    func backup(_ plan: BackupPlan) async -> [CopyRunResult] {
        guard !isBackupRunning else { return [] }
        let runStart = Date()
        var results: [CopyRunResult] = []
        var runErrors: [BackupFileError] = []
        var protectedTotal = 0
        for source in plan.sourceFolderURLs {
            let engine = CopyEngine(
                sourceURL: source,
                destinationURL: plan.destinationURL.appendingPathComponent(
                    source.lastPathComponent,
                    isDirectory: true
                ),
                stateURL: IncrementalIndex.indexFileURL(stateDirectory: runStateDirectory, source: source)
            )
            activeEngine = engine
            let result = await engine.run()
            results.append(result)
            runErrors += engine.state.errors
            protectedTotal += result.itemsProtected
            if result.outcome == .cancelled { break }
        }
        activeEngine = nil
        itemsProtected = protectedTotal
        if results.allSatisfy({ $0.outcome == .completed }) {
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
