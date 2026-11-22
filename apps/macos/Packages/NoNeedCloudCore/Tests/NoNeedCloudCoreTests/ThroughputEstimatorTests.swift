import Foundation
import Testing
@testable import NoNeedCloudCore

struct ThroughputEstimatorTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func noEstimateBeforeMinimumElapsed() {
        var estimator = ThroughputEstimator(window: 60, minimumElapsed: 20, minimumSpan: 5)
        for second in 0...10 {
            estimator.record(processed: second * 10, at: start.addingTimeInterval(Double(second)))
        }
        #expect(estimator.estimateRemaining(100, now: start.addingTimeInterval(10)) == nil)
    }

    @Test func estimateUsesSteadyRate() throws {
        var estimator = ThroughputEstimator(window: 60, minimumElapsed: 20, minimumSpan: 5)
        for second in 0...30 {
            estimator.record(processed: second * 10, at: start.addingTimeInterval(Double(second)))
        }
        let eta = try #require(estimator.estimateRemaining(100, now: start.addingTimeInterval(30)))
        #expect(abs(eta - 10) < 0.001)
    }

    @Test func onlyRecentWindowCounts() throws {
        var estimator = ThroughputEstimator(window: 10, minimumElapsed: 0, minimumSpan: 1)
        // Fast skipping for 30 s (100 items/s) …
        for second in 0...30 {
            estimator.record(processed: second * 100, at: start.addingTimeInterval(Double(second)))
        }
        // … then slow copying for 20 s (1 item/s).
        for second in 31...50 {
            estimator.record(processed: 3000 + (second - 30), at: start.addingTimeInterval(Double(second)))
        }
        let eta = try #require(estimator.estimateRemaining(60, now: start.addingTimeInterval(50)))
        #expect(abs(eta - 60) < 0.001)
    }

    @Test func stalledProgressGivesNoEstimate() {
        var estimator = ThroughputEstimator(window: 60, minimumElapsed: 0, minimumSpan: 1)
        for second in 0...30 {
            estimator.record(processed: 5, at: start.addingTimeInterval(Double(second)))
        }
        #expect(estimator.estimateRemaining(10, now: start.addingTimeInterval(30)) == nil)
    }
}
