import AppIntents
import Foundation

/// Static handle so AppIntents (which the system instantiates, so nothing can
/// be injected into them) can reach the live model. App.swift sets it during
/// launch, the same place it hands the model to ScheduleRunner.
@MainActor
enum AppModelAccess {
    static weak var shared: AppModel?

    static func plans() async -> [BackupPlan] { shared?.plans ?? [] }
}

/// Pure decision logic for the backup intents. Kept free of intent runtime so
/// tests exercise the mapping directly.
enum BackupIntentLogic {
    enum StartOutcome: Equatable {
        case started(BackupPlan)
        case alreadyRunning(BackupPlan)
        case nothingToBackUp(BackupPlan)
        case noPlan
    }

    enum StopOutcome: Equatable {
        case stopping
        case notRunning
    }

    /// The plan matching `planId`, or the first plan when the id is omitted or
    /// stale (the plan was deleted after the shortcut was made). nil only when
    /// there are no plans at all.
    static func resolvePlan(planId: UUID?, in plans: [BackupPlan]) -> BackupPlan? {
        guard !plans.isEmpty else { return nil }
        if let planId, let match = plans.first(where: { $0.id == planId }) { return match }
        return plans[0]
    }

    static func planEntities(in plans: [BackupPlan]) -> [PlanEntity] {
        plans.map { PlanEntity(id: $0.id, name: $0.name) }
    }

    static func entities(for identifiers: [UUID], in plans: [BackupPlan]) -> [PlanEntity] {
        identifiers.compactMap { id in
            plans.first(where: { $0.id == id }).map { PlanEntity(id: $0.id, name: $0.name) }
        }
    }

    static func classifyStart(
        planId: UUID?,
        in plans: [BackupPlan],
        isBackupRunning: Bool,
        isPlanRunning: (UUID) -> Bool
    ) -> StartOutcome {
        guard let plan = resolvePlan(planId: planId, in: plans) else { return .noPlan }
        if isBackupRunning || isPlanRunning(plan.id) { return .alreadyRunning(plan) }
        guard !plan.sources.isEmpty || plan.includePhotos else { return .nothingToBackUp(plan) }
        return .started(plan)
    }

    static func message(for outcome: StartOutcome) -> String {
        switch outcome {
        case .started(let plan): "Backup started: \(plan.name)."
        case .alreadyRunning: "A backup is already running."
        case .nothingToBackUp: "That plan has nothing to back up."
        case .noPlan: "No backup plan found in NoNeedCloud."
        }
    }

    static func classifyStop(isBackupRunning: Bool) -> StopOutcome {
        isBackupRunning ? .stopping : .notRunning
    }

    static func message(for outcome: StopOutcome) -> String {
        switch outcome {
        case .stopping: "Stopping the backup."
        case .notRunning: "No backup is running."
        }
    }
}

/// The backup plan offered to Shortcuts and Siri, backed by the plan's id and name.
struct PlanEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Backup Plan")
    static let defaultQuery = PlanQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    struct PlanQuery: EntityQuery {
        func entities(for identifiers: [UUID]) async throws -> [PlanEntity] {
            BackupIntentLogic.entities(for: identifiers, in: await AppModelAccess.plans())
        }

        func suggestedEntities() async throws -> [PlanEntity] {
            BackupIntentLogic.planEntities(in: await AppModelAccess.plans())
        }
    }
}

struct StartBackupIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Backup"
    static let description = IntentDescription("Starts a NoNeedCloud backup plan.")

    @Parameter(title: "Plan")
    var plan: PlanEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppModelAccess.shared else {
            return .result(dialog: IntentDialog(stringLiteral: "NoNeedCloud is not running."))
        }
        let outcome = BackupIntentLogic.classifyStart(
            planId: plan?.id,
            in: model.plans,
            isBackupRunning: model.isBackupRunning,
            isPlanRunning: { model.isPlanRunning($0) }
        )
        if case .started(let selected) = outcome {
            model.startBackup(selected)
        }
        return .result(dialog: IntentDialog(stringLiteral: BackupIntentLogic.message(for: outcome)))
    }
}

struct StopBackupIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Backup"
    static let description = IntentDescription("Stops the NoNeedCloud backup that is running.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppModelAccess.shared else {
            return .result(dialog: IntentDialog(stringLiteral: "NoNeedCloud is not running."))
        }
        let outcome = BackupIntentLogic.classifyStop(isBackupRunning: model.isBackupRunning)
        if outcome == .stopping {
            model.stopBackup()
        }
        return .result(dialog: IntentDialog(stringLiteral: BackupIntentLogic.message(for: outcome)))
    }
}
