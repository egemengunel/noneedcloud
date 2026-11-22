import Foundation
import Testing
@testable import NoNeedCloud

struct PlanStoreTests {
    @Test func loadPlansReturnsEmptyWhenNoFileExists() throws {
        try TestSupport.withTempStore { store, _ in
            let plans = try store.loadPlans()
            #expect(plans.isEmpty)
        }
    }

    @Test func saveThenLoadRoundTripsPlan() throws {
        try TestSupport.withTempStore { store, _ in
            let plan = TestSupport.makePlan()
            try store.savePlans([plan])
            let loaded = try store.loadPlans()
            #expect(loaded == [plan])
        }
    }

    @Test func savingReplacesExistingPlans() throws {
        try TestSupport.withTempStore { store, _ in
            try store.savePlans([TestSupport.makePlan(name: "First")])
            try store.savePlans([TestSupport.makePlan(name: "Second")])
            let loaded = try store.loadPlans()
            #expect(loaded.count == 1)
            #expect(loaded[0].name == "Second")
        }
    }

    @Test func corruptPlansFileThrowsOnLoad() throws {
        try TestSupport.withTempStore { store, dir in
            try Data("not json".utf8).write(to: dir.appendingPathComponent("plans.json"))
            #expect(throws: (any Error).self) {
                try store.loadPlans()
            }
        }
    }

    @Test func setupCompletedDefaultsToFalse() throws {
        try TestSupport.withTempStore { store, _ in
            #expect(!store.loadSetupCompleted())
        }
    }

    @Test func setSetupCompletedPersistsAcrossInstances() throws {
        try TestSupport.withTempStore { store, dir in
            try store.setSetupCompleted(true)
            #expect(JSONPlanStore(directory: dir).loadSetupCompleted())
        }
    }

    @Test func setupFlagCanBeReset() throws {
        try TestSupport.withTempStore { store, _ in
            try store.setSetupCompleted(true)
            try store.setSetupCompleted(false)
            #expect(!store.loadSetupCompleted())
        }
    }

    @Test func corruptSetupFileLoadsAsFalse() throws {
        try TestSupport.withTempStore { store, dir in
            try Data("garbage".utf8).write(to: dir.appendingPathComponent("setup.json"))
            #expect(!store.loadSetupCompleted())
        }
    }
}
