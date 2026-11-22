import Foundation

protocol RunHistoryStore: AnyObject {
    func loadRecords() throws -> [BackupRunRecord]
    func append(_ record: BackupRunRecord) throws
}

final class JSONRunHistoryStore: RunHistoryStore {
    private let directory: URL
    private let recordsURL: URL

    init(directory: URL) {
        self.directory = directory
        recordsURL = directory.appendingPathComponent("history.json")
    }

    func loadRecords() throws -> [BackupRunRecord] {
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [] }
        let data = try Data(contentsOf: recordsURL)
        return try JSONDecoder().decode([BackupRunRecord].self, from: data)
    }

    func append(_ record: BackupRunRecord) throws {
        var records = try loadRecords()
        records.append(record)
        let data = try JSONEncoder().encode(records)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: recordsURL, options: .atomic)
    }
}
