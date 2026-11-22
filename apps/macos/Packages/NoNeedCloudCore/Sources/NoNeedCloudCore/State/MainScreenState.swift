import Foundation

/// Setup steps shown in the main window until the first backup has run (UX spec §3).
public enum SetupStep: Int, CaseIterable, Sendable {
    case sources = 1
    case destination = 2
    case firstBackup = 3
}

/// Problems that put the main window into the "Needs attention" state.
public enum AttentionIssue: Equatable, Sendable {
    case destinationUnavailable(name: String)
    case photosAccessDenied
    case lastRunFailed(reason: String)
    case backupStale(days: Int)
}

/// Facts about the outside world the app checks before deciding what to show.
public struct HealthSnapshot: Equatable, Sendable {
    public var destinationAvailable: Bool
    /// nil = not asked yet.
    public var photosAccessGranted: Bool?

    public init(destinationAvailable: Bool = true, photosAccessGranted: Bool? = nil) {
        self.destinationAvailable = destinationAvailable
        self.photosAccessGranted = photosAccessGranted
    }
}

/// Which state the main window's status area is in. Derived, never stored.
public enum MainScreenState: Equatable, Sendable {
    case setup(SetupStep)
    case running
    case protected
    case needsAttention(AttentionIssue)

    public static let staleAfterDays = 7

    public static func derive(
        plan: BackupPlan,
        runs: [BackupRun],
        isRunning: Bool,
        health: HealthSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> MainScreenState {
        if isRunning { return .running }
        guard plan.hasSources else { return .setup(.sources) }
        guard let destination = plan.destination else { return .setup(.destination) }

        let planRuns = runs.filter { $0.planID == plan.id }.sorted { $0.finishedAt < $1.finishedAt }
        let lastRun = planRuns.last
        let lastCompleted = planRuns.last(where: \.didComplete)

        if !health.destinationAvailable {
            return .needsAttention(.destinationUnavailable(name: destination.displayName))
        }
        if plan.photos.isEnabled, health.photosAccessGranted == false {
            return .needsAttention(.photosAccessDenied)
        }
        if let lastRun, lastRun.outcome == .failed {
            return .needsAttention(.lastRunFailed(reason: lastRun.failureReason ?? "The backup stopped unexpectedly."))
        }
        guard let lastCompleted else { return .setup(.firstBackup) }

        let days = calendar.dateComponents([.day], from: lastCompleted.finishedAt, to: now).day ?? 0
        if days >= staleAfterDays {
            return .needsAttention(.backupStale(days: days))
        }
        return .protected
    }

    public var setupStep: SetupStep? {
        if case let .setup(step) = self { step } else { nil }
    }
}
