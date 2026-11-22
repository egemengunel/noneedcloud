import Foundation

protocol PlanStore: AnyObject {
    func loadPlans() throws -> [BackupPlan]
    func savePlans(_ plans: [BackupPlan]) throws
    func loadSetupCompleted() -> Bool
    func setSetupCompleted(_ completed: Bool) throws
}

private struct SetupFlag: Codable {
    var setupCompleted: Bool
}

final class JSONPlanStore: PlanStore {
    private let directory: URL
    private let plansURL: URL
    private let setupURL: URL

    init(directory: URL) {
        self.directory = directory
        self.plansURL = directory.appendingPathComponent("plans.json")
        self.setupURL = directory.appendingPathComponent("setup.json")
    }

    static func makeDefault() -> JSONPlanStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONPlanStore(directory: appSupport.appendingPathComponent("NoNeedCloud", isDirectory: true))
    }

    func loadPlans() throws -> [BackupPlan] {
        guard FileManager.default.fileExists(atPath: plansURL.path) else { return [] }
        let data = try Data(contentsOf: plansURL)
        return try JSONDecoder().decode([BackupPlan].self, from: data)
    }

    func savePlans(_ plans: [BackupPlan]) throws {
        let data = try JSONEncoder().encode(plans)
        try write(data, to: plansURL)
    }

    func loadSetupCompleted() -> Bool {
        guard FileManager.default.fileExists(atPath: setupURL.path),
              let data = try? Data(contentsOf: setupURL),
              let flag = try? JSONDecoder().decode(SetupFlag.self, from: data)
        else { return false }
        return flag.setupCompleted
    }

    func setSetupCompleted(_ completed: Bool) throws {
        let data = try JSONEncoder().encode(SetupFlag(setupCompleted: completed))
        try write(data, to: setupURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
