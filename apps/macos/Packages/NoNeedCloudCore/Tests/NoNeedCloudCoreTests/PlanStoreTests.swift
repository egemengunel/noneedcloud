import Foundation
import Testing
@testable import NoNeedCloudCore

struct PlanStoreTests {
    @Test func emptyWhenNoFilesExist() throws {
        try TestSupport.withTempStore { store, _ in
            let plans = try store.loadPlans()
            let runs = try store.loadRuns()
            #expect(plans.isEmpty)
            #expect(runs.isEmpty)
        }
    }

    @Test func plansRoundTrip() throws {
        try TestSupport.withTempStore { store, dir in
            let plan = TestSupport.makePlan()
            try store.savePlans([plan])
            let loaded = try JSONPlanStore(directory: dir).loadPlans()
            #expect(loaded == [plan])
        }
    }

    @Test func runsRoundTrip() throws {
        try TestSupport.withTempStore { store, dir in
            let run = TestSupport.run(
                for: TestSupport.makePlan(),
                outcome: .completedWithErrors,
                finishedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            try store.saveRuns([run])
            let loaded = try JSONPlanStore(directory: dir).loadRuns()
            #expect(loaded == [run])
        }
    }

    @Test func savingReplacesExistingPlans() throws {
        try TestSupport.withTempStore { store, _ in
            try store.savePlans([TestSupport.makePlan(name: "First")])
            try store.savePlans([TestSupport.makePlan(name: "Second")])
            let loaded = try store.loadPlans()
            #expect(loaded.map(\.name) == ["Second"])
        }
    }

    @Test func corruptPlansFileThrows() throws {
        try TestSupport.withTempStore { store, dir in
            try Data("not json".utf8).write(to: dir.appendingPathComponent("plans.json"))
            #expect(throws: (any Error).self) { try store.loadPlans() }
        }
    }
}
