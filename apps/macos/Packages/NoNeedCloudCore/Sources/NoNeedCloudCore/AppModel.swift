import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    @ObservationIgnored public let store: any PlanStore

    public private(set) var plans: [BackupPlan]
    public private(set) var isSetupCompleted: Bool

    public init(store: any PlanStore) {
        self.store = store
        plans = (try? store.loadPlans()) ?? []
        isSetupCompleted = store.loadSetupCompleted()
    }

    public var isSetupNeeded: Bool {
        plans.isEmpty && !isSetupCompleted
    }

    public func finishSetup(_ plan: BackupPlan) {
        plans.append(plan)
        isSetupCompleted = true
        try? store.savePlans(plans)
        try? store.setSetupCompleted(true)
    }
}
