import Foundation
import Testing
@testable import NoNeedCloud

struct MenuBarViewModelTests {
    @Test func iconReflectsBackupRunningState() {
        #expect(MenuBarViewModel.icon(isBackupRunning: false) == "arrow.down.circle")
        #expect(MenuBarViewModel.icon(isBackupRunning: true) == "arrow.down.circle.fill")
    }

    @Test func lastRunLabelWithoutRunIsNever() {
        #expect(MenuBarViewModel.lastRunLabel(lastRun: nil) == "Never")
    }

    @Test func lastRunLabelRendersFormattedDateWhenRunExists() {
        let label = MenuBarViewModel.lastRunLabel(lastRun: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!label.isEmpty)
        #expect(label != "Never")
    }

    @Test func planRowsAreSortedByNameWithRunStateAndLastRunLabels() {
        let alpha = TestSupport.makePlan(name: "Alpha")
        let beta = TestSupport.makePlan(name: "beta")
        let zeta = TestSupport.makePlan(name: "Zeta")

        let rows = MenuBarViewModel.planRows(
            plans: [zeta, beta, alpha],
            runningPlanIds: [alpha.id],
            lastRun: { $0 == alpha.id ? Date(timeIntervalSince1970: 1_700_000_000) : nil }
        )

        #expect(rows.map(\.name) == ["Alpha", "beta", "Zeta"])
        #expect(rows[0].id == alpha.id)
        #expect(rows[0].isRunning)
        #expect(rows[0].lastRunLabel != "Never")
        #expect(!rows[1].isRunning)
        #expect(rows[1].lastRunLabel == "Never")
    }
}
