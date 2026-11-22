import Foundation
import Testing
@testable import NoNeedCloud

struct BackupIntentLogicTests {
    private var planA: BackupPlan { TestSupport.makePlan(name: "Photos") }
    private var planB: BackupPlan { TestSupport.makePlan(name: "Documents") }

    @Test func resolvePlanMatchesByIdAndFallsBackToFirst() {
        let a = planA, b = planB
        #expect(BackupIntentLogic.resolvePlan(planId: a.id, in: [a, b])?.id == a.id)
        #expect(BackupIntentLogic.resolvePlan(planId: b.id, in: [a, b])?.id == b.id)
        #expect(BackupIntentLogic.resolvePlan(planId: nil, in: [a, b])?.id == a.id)
        #expect(BackupIntentLogic.resolvePlan(planId: UUID(), in: [a, b])?.id == a.id)
        #expect(BackupIntentLogic.resolvePlan(planId: nil, in: []) == nil)
        #expect(BackupIntentLogic.resolvePlan(planId: UUID(), in: []) == nil)
    }

    @Test func planEntitiesCarryPlanIdAndName() {
        let a = planA, b = planB
        let entities = BackupIntentLogic.planEntities(in: [a, b])
        #expect(entities.map(\.id) == [a.id, b.id])
        #expect(entities.map(\.name) == ["Photos", "Documents"])
    }

    @Test func entitiesForIdentifiersSelectsOnlyKnownPlans() {
        let a = planA, b = planB
        let entities = BackupIntentLogic.entities(for: [a.id, UUID(), b.id], in: [a, b])
        #expect(entities.map(\.id) == [a.id, b.id])
        #expect(entities.map(\.name) == ["Photos", "Documents"])
        #expect(BackupIntentLogic.entities(for: [], in: [a, b]).isEmpty)
    }

    @Test func classifyStartStartsTheResolvedPlanWhenIdle() {
        let a = planA
        let outcome = BackupIntentLogic.classifyStart(
            planId: a.id,
            in: [a],
            isBackupRunning: false,
            isPlanRunning: { _ in false }
        )
        #expect(outcome == .started(a))
    }

    @Test func classifyStartFallsBackToFirstPlanWhenOmitted() {
        let a = planA, b = planB
        let outcome = BackupIntentLogic.classifyStart(
            planId: nil,
            in: [a, b],
            isBackupRunning: false,
            isPlanRunning: { _ in false }
        )
        #expect(outcome == .started(a))
    }

    @Test func classifyStartReportsAlreadyRunning() {
        let a = planA
        #expect(BackupIntentLogic.classifyStart(planId: nil, in: [a], isBackupRunning: true, isPlanRunning: { _ in false }) == .alreadyRunning(a))
        #expect(BackupIntentLogic.classifyStart(planId: nil, in: [a], isBackupRunning: false, isPlanRunning: { _ in true }) == .alreadyRunning(a))
    }

    @Test func classifyStartRejectsPlanWithNothingToProtect() {
        var empty = TestSupport.makePlan(name: "Empty", sources: [])
        empty.includePhotos = false
        let outcome = BackupIntentLogic.classifyStart(planId: nil, in: [empty], isBackupRunning: false, isPlanRunning: { _ in false })
        #expect(outcome == .nothingToBackUp(empty))
    }

    @Test func classifyStartReportsNoPlanWhenNoneExist() {
        #expect(BackupIntentLogic.classifyStart(planId: nil, in: [], isBackupRunning: false, isPlanRunning: { _ in false }) == .noPlan)
    }

    @Test func startMessagesAreBriefAndNameThePlan() {
        let a = planA
        #expect(BackupIntentLogic.message(for: .started(a)) == "Backup started: Photos.")
        #expect(BackupIntentLogic.message(for: .alreadyRunning(a)) == "A backup is already running.")
        #expect(BackupIntentLogic.message(for: .nothingToBackUp(a)) == "That plan has nothing to back up.")
        #expect(BackupIntentLogic.message(for: .noPlan) == "No backup plan found in NoNeedCloud.")
    }

    @Test func stopClassificationAndMessages() {
        #expect(BackupIntentLogic.classifyStop(isBackupRunning: true) == .stopping)
        #expect(BackupIntentLogic.classifyStop(isBackupRunning: false) == .notRunning)
        #expect(BackupIntentLogic.message(for: .stopping) == "Stopping the backup.")
        #expect(BackupIntentLogic.message(for: .notRunning) == "No backup is running.")
    }
}
