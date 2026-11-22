import Foundation
import Testing
@testable import NoNeedCloud

struct AppModelTests {
    @Test func freshInstallNeedsSetup() throws {
        try TestSupport.withTempStore { store, _ in
            let model = AppModel(store: store)
            #expect(model.isSetupNeeded)
            #expect(model.plans.isEmpty)
        }
    }

    @Test func completedSetupFlagSkipsSetupEvenWithoutPlans() throws {
        try TestSupport.withTempStore { store, _ in
            try store.setSetupCompleted(true)
            let model = AppModel(store: store)
            #expect(!model.isSetupNeeded)
        }
    }

    @Test func existingPlansSkipSetup() throws {
        try TestSupport.withTempStore { store, _ in
            try store.savePlans([TestSupport.makePlan()])
            let model = AppModel(store: store)
            #expect(!model.isSetupNeeded)
        }
    }

    @Test func finishSetupAddsPlanAndPersistsEverything() throws {
        try TestSupport.withTempStore { store, dir in
            let model = AppModel(store: store)
            let plan = TestSupport.makePlan(name: "My First Backup")

            model.finishSetup(plan)

            #expect(model.plans == [plan])
            #expect(model.isSetupCompleted)
            #expect(!model.isSetupNeeded)

            let relaunched = AppModel(store: JSONPlanStore(directory: dir))
            #expect(relaunched.plans == [plan])
            #expect(relaunched.isSetupCompleted)
            #expect(!relaunched.isSetupNeeded)
        }
    }
}
