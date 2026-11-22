import Foundation

/// Runs one backup plan and publishes progress.
///
/// The stream emits progress updates as fast as the engine likes (the UI
/// throttles), ends with a value whose phase is `.finished`, and throws if the
/// run can't continue at all (e.g. the destination disappeared). Cancelling the
/// consuming task stops the run; the engine must not leave a partial file at a
/// final name.
public protocol BackupEngine: Sendable {
    func run(_ plan: BackupPlan) -> AsyncThrowingStream<BackupProgress, any Error>
}
