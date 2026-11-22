import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: any PlanStore
    let runStateDirectory: URL

    @Published private(set) var plans: [BackupPlan]
    @Published private(set) var isSetupCompleted: Bool
    @Published private(set) var activeEngine: CopyEngine?
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var itemsProtected = 0

    init(store: any PlanStore, runStateDirectory: URL? = nil) {
        self.store = store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.runStateDirectory = runStateDirectory
            ?? appSupport.appendingPathComponent("NoNeedCloud/RunState", isDirectory: true)
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
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

    @discardableResult
    func backup(_ plan: BackupPlan) async -> [CopyRunResult] {
        guard !isBackupRunning else { return [] }
        var results: [CopyRunResult] = []
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
            protectedTotal += result.itemsProtected
            if result.outcome == .cancelled { break }
        }
        activeEngine = nil
        itemsProtected = protectedTotal
        if results.allSatisfy({ $0.outcome == .completed }) {
            lastBackupDate = Date()
        }
        return results
    }
}
