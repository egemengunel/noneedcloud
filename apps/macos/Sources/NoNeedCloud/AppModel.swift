import Combine
import Foundation

final class AppModel: ObservableObject {
    let store: any PlanStore

    @Published private(set) var plans: [BackupPlan]
    @Published private(set) var isSetupCompleted: Bool

    init(store: any PlanStore) {
        self.store = store
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
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
}
