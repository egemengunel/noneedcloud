import Foundation

/// Persists backup plans and run history.
public protocol PlanStore: AnyObject, Sendable {
    func loadPlans() throws -> [BackupPlan]
    func savePlans(_ plans: [BackupPlan]) throws
    func loadRuns() throws -> [BackupRun]
    func saveRuns(_ runs: [BackupRun]) throws
}

/// JSON files in Application Support (inside the sandbox container).
/// Run history moves to SQLite with the real engine's index (M2/M3).
public final class JSONPlanStore: PlanStore {
    private let directory: URL
    private let plansURL: URL
    private let runsURL: URL

    public init(directory: URL) {
        self.directory = directory
        self.plansURL = directory.appendingPathComponent("plans.json")
        self.runsURL = directory.appendingPathComponent("runs.json")
    }

    public static func makeDefault() -> JSONPlanStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONPlanStore(directory: appSupport.appendingPathComponent("NoNeedCloud", isDirectory: true))
    }

    public func loadPlans() throws -> [BackupPlan] { try load(plansURL) ?? [] }
    public func savePlans(_ plans: [BackupPlan]) throws { try save(plans, to: plansURL) }
    public func loadRuns() throws -> [BackupRun] { try load(runsURL) ?? [] }
    public func saveRuns(_ runs: [BackupRun]) throws { try save(runs, to: runsURL) }

    private func load<T: Decodable>(_ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func save(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
