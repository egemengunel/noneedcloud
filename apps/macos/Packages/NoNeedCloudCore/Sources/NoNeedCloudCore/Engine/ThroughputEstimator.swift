import Foundation

/// Estimates time remaining from *recent* throughput (UX spec §5.2).
///
/// Skipped items are much faster than copied ones, so averaging since the start
/// would be badly wrong; only the last `window` of samples is used. No estimate
/// is given until `minimumElapsed` has passed, or while the recent samples span
/// less than `minimumSpan`.
public struct ThroughputEstimator: Sendable {
    public var window: TimeInterval
    public var minimumElapsed: TimeInterval
    public var minimumSpan: TimeInterval

    private var startedAt: Date?
    private var samples: [(date: Date, processed: Int)] = []

    public init(window: TimeInterval = 60, minimumElapsed: TimeInterval = 20, minimumSpan: TimeInterval = 5) {
        self.window = window
        self.minimumElapsed = minimumElapsed
        self.minimumSpan = minimumSpan
    }

    public mutating func record(processed: Int, at date: Date) {
        if startedAt == nil { startedAt = date }
        samples.append((date, processed))
        let cutoff = date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    /// Seconds until `remaining` more items are processed, or nil if not yet known.
    public func estimateRemaining(_ remaining: Int, now: Date) -> TimeInterval? {
        guard let startedAt, now.timeIntervalSince(startedAt) >= minimumElapsed,
              let first = samples.first, let last = samples.last
        else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        let done = last.processed - first.processed
        guard span >= minimumSpan, done > 0 else { return nil }
        if remaining <= 0 { return 0 }
        return Double(remaining) / (Double(done) / span)
    }
}
