import AppKit
import Foundation

/// The subset of AppModel the scheduler needs. Lets tests drive ScheduleRunner
/// with a spy instead of a live model.
@MainActor
protocol PlanScheduling: AnyObject {
    var plans: [BackupPlan] { get }
    func isPlanRunning(_ planId: UUID) -> Bool
    func lastRunDate(for planId: UUID) -> Date?
    func startBackup(_ plan: BackupPlan)
}

/// Ticks scheduled plans and starts the ones that are due. A plan the Mac
/// slept through is started once: its due date stays in the past until the run
/// completes, and the anchor then re-anchors to the completion time (see
/// ScheduleCalculator), so no stampede after wake.
@MainActor
final class ScheduleRunner {
    private let scheduler: any PlanScheduling
    private let calendar: Calendar
    private let clock: () -> Date
    private var tickerTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    static let tickInterval: TimeInterval = 60

    init(
        scheduler: any PlanScheduling,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.clock = clock
    }

    func start() {
        guard tickerTask == nil else { return }
        tick()
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard !Task.isCancelled else { break }
                self.tick()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stop() {
        tickerTask?.cancel()
        tickerTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func tick() {
        let now = clock()
        for plan in scheduler.plans {
            guard plan.schedule.isScheduled, !scheduler.isPlanRunning(plan.id) else { continue }
            guard let due = ScheduleCalculator.nextRun(
                after: now,
                schedule: plan.schedule,
                lastRun: scheduler.lastRunDate(for: plan.id),
                calendar: calendar
            ), now >= due else { continue }
            scheduler.startBackup(plan)
        }
    }
}
