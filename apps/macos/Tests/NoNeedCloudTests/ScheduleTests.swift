import Foundation
import Testing
@testable import NoNeedCloud

struct ScheduleTests {
    @Test func legacyManualStringDecodes() throws {
        let schedule = try JSONDecoder().decode(Schedule.self, from: Data(#""manual""#.utf8))
        #expect(schedule == .manual)
    }

    @Test func manualEncodesAsLegacyString() throws {
        let data = try JSONEncoder().encode(Schedule.manual)
        #expect(String(data: data, encoding: .utf8) == #""manual""#)
    }

    @Test func scheduledCasesRoundTripThroughNewEncoding() throws {
        let schedules: [Schedule] = [
            .hourly,
            .daily(hour: 9, minute: 30),
            .weekly(weekday: 2, hour: 7, minute: 15),
            .monthly(day: 31, hour: 23, minute: 59),
        ]
        for schedule in schedules {
            let data = try JSONEncoder().encode(schedule)
            let decoded = try JSONDecoder().decode(Schedule.self, from: data)
            #expect(decoded == schedule)
        }
    }

    @Test func dailyEncodingCarriesKindAndFields() throws {
        let json = String(data: try JSONEncoder().encode(Schedule.daily(hour: 9, minute: 0)), encoding: .utf8) ?? ""
        #expect(json.contains("\"kind\""))
        #expect(json.contains("\"daily\""))
        #expect(json.contains("\"hour\""))
        #expect(json.contains("\"minute\""))
    }

    @Test func unknownKindThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Schedule.self, from: Data(#"{"kind":"yearly"}"#.utf8))
        }
    }

    @Test func legacyUnknownStringThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Schedule.self, from: Data(#""weekly""#.utf8))
        }
    }

    @Test func legacyPlanJSONWithManualScheduleDecodes() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Legacy Plan","sourceFolderURLs":["/tmp/src"],"includePhotos":false,"photoOptions":{},"destinationURL":"/tmp/dest","schedule":"manual"}]
        """
        let plans = try JSONDecoder().decode([BackupPlan].self, from: Data(json.utf8))
        #expect(plans.count == 1)
        #expect(plans[0].schedule == .manual)
        #expect(plans[0].sourceFolderURLs.map(\.path) == ["/tmp/src"])
    }

    @Test func legacyPlanJSONWithoutScheduleKeyDefaultsToManual() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Legacy Plan","sourceFolderURLs":["/tmp/src"],"includePhotos":false,"photoOptions":{},"destinationURL":"/tmp/dest"}]
        """
        let plans = try JSONDecoder().decode([BackupPlan].self, from: Data(json.utf8))
        #expect(plans.count == 1)
        #expect(plans[0].schedule == .manual)
    }

    @Test func storeRoundTripsScheduledPlan() throws {
        try TestSupport.withTempStore { store, _ in
            var plan = TestSupport.makePlan()
            plan.schedule = .daily(hour: 9, minute: 0)
            try store.savePlans([plan])
            #expect(try store.loadPlans() == [plan])
        }
    }

    @Test func summariesDescribeEachSchedule() {
        #expect(Schedule.manual.summary == "Manual")
        #expect(Schedule.hourly.summary == "Every hour")
        #expect(Schedule.daily(hour: 9, minute: 0).summary.contains("09:00"))
        #expect(Schedule.weekly(weekday: 2, hour: 9, minute: 0).summary.contains("Monday"))
        #expect(Schedule.monthly(day: 31, hour: 9, minute: 0).summary.contains("31"))
    }

    @Test func onlyManualIsUnscheduled() {
        #expect(!Schedule.manual.isScheduled)
        #expect(Schedule.hourly.isScheduled)
        #expect(Schedule.daily(hour: 9, minute: 0).isScheduled)
        #expect(Schedule.weekly(weekday: 1, hour: 9, minute: 0).isScheduled)
        #expect(Schedule.monthly(day: 15, hour: 9, minute: 0).isScheduled)
    }
}
