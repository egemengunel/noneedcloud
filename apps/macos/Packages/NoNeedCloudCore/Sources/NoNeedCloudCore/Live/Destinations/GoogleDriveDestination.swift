import Foundation

/// Google Drive (Drive API v3) destination. Health check reads the About
/// endpoint; folders are resolved stepwise (find-or-create) and files upload
/// as small multipart requests so name and parent are set in one call.
final class GoogleDriveDestination: BackupDestination, @unchecked Sendable {
    static let apiRoot = "https://www.googleapis.com/drive/v3"
    static let uploadRoot = "https://www.googleapis.com/upload/drive/v3"
    static let folderMIMEType = "application/vnd.google-apps.folder"

    let config: CloudTokenConfig
    private let keychain: any KeychainStore
    private let httpClient: any HTTPClient
    private let lock = NSLock()
    private var folderIdsByPath: [String: String] = [:]

    init(config: CloudTokenConfig, keychain: any KeychainStore, httpClient: any HTTPClient) {
        self.config = config
        self.keychain = keychain
        self.httpClient = httpClient
    }

    var label: String { "Google Drive" }

    func healthCheck() async throws {
        let token = try accessToken()
        guard let url = URL(string: "\(Self.apiRoot)/about?fields=user") else {
            throw DestinationError("Google Drive health check failed: invalid API URL.")
        }
        let request = CloudHTTPRequest(
            method: "GET",
            url: url,
            headers: ["Authorization": "Bearer \(token)"]
        )
        let response = try await send(request, context: "Google Drive health check")
        guard response.isSuccess else {
            throw DestinationError(Self.healthCheckFailureMessage(status: response.status, response: response))
        }
    }

    func ensureDirectory(relPath: String) async throws {
        _ = try await folderID(forPath: relPath, createIfMissing: true)
    }

    func copyFile(relPath: String, fromFile: URL, sourceModificationDate: Date, isCancelled: @escaping @Sendable () -> Bool) async throws {
        let token = try accessToken()
        let parentID = try await folderID(forPath: Self.parentDirectory(of: relPath), createIfMissing: true)
        let metadata = try JSONSerialization.data(
            withJSONObject: ["name": Self.lastComponent(of: relPath), "parents": [parentID]]
        )
        let boundary = "noneedcloud-\(UUID().uuidString)"
        let bodyURL = try Self.writeMultipartBody(metadata: metadata, fileURL: fromFile, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        guard let uploadURL = URL(string: "\(Self.uploadRoot)/files?uploadType=multipart") else {
            throw DestinationError("Google Drive upload failed: could not build the upload URL for \"\(relPath)\".")
        }
        let request = CloudHTTPRequest(
            method: "POST",
            url: uploadURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "multipart/related; boundary=\(boundary)",
            ],
            bodyFileURL: bodyURL
        )
        let response = try await send(request, context: "Google Drive upload of \"\(relPath)\"")
        guard response.isSuccess else {
            throw DestinationError(
                "Google Drive upload failed for \"\(relPath)\": HTTP \(response.status). \(response.bodySnippet)"
            )
        }
    }

    func destinationFileExists(relPath: String) -> Bool { false }

    // MARK: - Pure mapping helpers

    static func parentDirectory(of relPath: String) -> String {
        guard let index = relPath.lastIndex(of: "/") else { return "" }
        return String(relPath[..<index])
    }

    static func lastComponent(of relPath: String) -> String {
        guard let index = relPath.lastIndex(of: "/") else { return relPath }
        return String(relPath[index...].dropFirst())
    }

    /// Streams metadata + media into one multipart/related body file so the
    /// upload can go over URLSession's file-based (streaming) task.
    static func writeMultipartBody(metadata: Data, fileURL: URL, boundary: String) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("noneedcloud-upload-\(UUID().uuidString)", isDirectory: false)
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw DestinationError("Google Drive upload failed: could not create a temporary upload file.")
        }
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        try output.write(contentsOf: metadata)
        try output.write(contentsOf: Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    static func healthCheckFailureMessage(status: Int, response: CloudHTTPResponse) -> String {
        if status == 401 || status == 403 {
            return "Google Drive health check failed: the access token is invalid or lacks the Drive scope (HTTP \(status)). Paste a fresh token in the plan editor."
        }
        return "Google Drive health check failed: HTTP \(status). \(response.bodySnippet)"
    }

    // MARK: - Internals

    private func folderID(forPath path: String, createIfMissing: Bool) async throws -> String {
        guard !path.isEmpty else { return "root" }
        if let cached = cachedFolderID(forPath: path) { return cached }
        var parentID = "root"
        var accumulated = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            if let cached = cachedFolderID(forPath: accumulated) {
                parentID = cached
                continue
            }
            parentID = try await findOrCreateFolder(named: String(component), parentID: parentID)
            setFolderID(parentID, forPath: accumulated)
        }
        return parentID
    }

    private func findOrCreateFolder(named name: String, parentID: String) async throws -> String {
        let token = try accessToken()
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let query = "name = '\(escapedName)' and '\(parentID)' in parents and mimeType = '\(Self.folderMIMEType)' and trashed = false"
        guard var components = URLComponents(string: "\(Self.apiRoot)/files") else {
            throw DestinationError("Google Drive folder lookup failed: could not build the query URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id)"),
        ]
        guard let findURL = components.url else {
            throw DestinationError("Google Drive folder lookup failed: could not build the query URL.")
        }
        let findRequest = CloudHTTPRequest(
            method: "GET",
            url: findURL,
            headers: ["Authorization": "Bearer \(token)"]
        )
        let findResponse = try await send(findRequest, context: "Google Drive folder lookup")
        guard findResponse.isSuccess else {
            throw DestinationError(
                "Google Drive folder lookup failed: HTTP \(findResponse.status). \(findResponse.bodySnippet)"
            )
        }
        if let json = try? JSONSerialization.jsonObject(with: findResponse.data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let existingID = files.first?["id"] as? String, !existingID.isEmpty {
            return existingID
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["name": name, "mimeType": Self.folderMIMEType, "parents": [parentID]]
        )
        guard let createURL = URL(string: "\(Self.apiRoot)/files") else {
            throw DestinationError("Google Drive folder creation failed for \"\(name)\": could not build the request URL.")
        }
        let createRequest = CloudHTTPRequest(
            method: "POST",
            url: createURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
            ],
            bodyData: body
        )
        let createResponse = try await send(createRequest, context: "Google Drive folder creation")
        guard createResponse.isSuccess,
              let json = try? JSONSerialization.jsonObject(with: createResponse.data) as? [String: Any],
              let newID = json["id"] as? String, !newID.isEmpty else {
            throw DestinationError(
                "Google Drive folder creation failed for \"\(name)\": HTTP \(createResponse.status). \(createResponse.bodySnippet)"
            )
        }
        return newID
    }

    private func accessToken() throws -> String {
        guard let data = try keychain.load(account: config.secretRef),
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw DestinationError(
                "Google Drive access token is missing from the Keychain. Paste a fresh token for this destination."
            )
        }
        return token
    }

    private func send(_ request: CloudHTTPRequest, context: String) async throws -> CloudHTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch {
            throw DestinationError("\(context) failed: \(error.localizedDescription). Google Drive may be unreachable.")
        }
    }

    private func cachedFolderID(forPath key: String) -> String? {
        lock.withLock { folderIdsByPath[key] }
    }

    private func setFolderID(_ id: String, forPath key: String) {
        lock.withLock { folderIdsByPath[key] = id }
    }
}
