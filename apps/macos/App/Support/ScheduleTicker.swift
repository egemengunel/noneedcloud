import AppKit
import NoNeedCloudCore

/// Checks once a minute, and whenever the Mac wakes, whether a scheduled
/// backup is due. A time the Mac slept through runs once on wake.
@MainActor
final class ScheduleTicker {
    private let model: AppModel
    private var task: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    init(model: AppModel) {
        self.model = model
        tick()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.tick()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Give volumes and the network a moment to come back.
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    await self.model.refreshHealth()
                    self.tick()
                }
            }
        }
    }

    isolated deinit {
        task?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func tick() {
        model.runScheduledBackupIfDue()
    }
}
