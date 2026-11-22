import Foundation

/// OneDrive (Microsoft Graph) destination. Health check reads /me; uploads
/// PUT the file to root:/{path}:/content, which creates parent folders.
final class OneDriveDestination: BackupDestination {
    static let apiRoot = "https://graph.microsoft.com/v1.0"

    let config: CloudTokenConfig
    private let keychain: any KeychainStore
    private let httpClient: any HTTPClient

    init(config: CloudTokenConfig, keychain: any KeychainStore, httpClient: any HTTPClient) {
        self.config = config
        self.keychain = keychain
        self.httpClient = httpClient
    }

    var label: String { "OneDrive" }

    func healthCheck() async throws {
        let token = try accessToken()
        guard let url = URL(string: "\(Self.apiRoot)/me") else {
            throw DestinationError("OneDrive health check failed: invalid API URL.")
        }
        let request = CloudHTTPRequest(
            method: "GET",
            url: url,
            headers: ["Authorization": "Bearer \(token)"]
        )
        let response = try await send(request, context: "OneDrive health check")
        guard response.isSuccess else {
            throw DestinationError(Self.healthCheckFailureMessage(status: response.status, response: response))
        }
    }

    func ensureDirectory(relPath: String) async throws {}

    func copyFile(relPath: String, fromFile: URL, sourceModificationDate: Date, isCancelled: @escaping @Sendable () -> Bool) async throws {
        let token = try accessToken()
        var components = URLComponents(string: "\(Self.apiRoot)")!
        components.percentEncodedPath = "/v1.0/me/drive/root:/\(Self.encodedObjectPath(relPath)):/content"
        let request = CloudHTTPRequest(
            method: "PUT",
            url: components.url!,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/octet-stream",
            ],
            bodyFileURL: fromFile
        )
        let response = try await send(request, context: "OneDrive upload of \"\(relPath)\"")
        guard response.isSuccess else {
            throw DestinationError(
                "OneDrive upload failed for \"\(relPath)\": HTTP \(response.status). \(response.bodySnippet)"
            )
        }
    }

    func destinationFileExists(relPath: String) -> Bool { false }

    // MARK: - Pure mapping helpers

    static func encodedObjectPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    static func healthCheckFailureMessage(status: Int, response: CloudHTTPResponse) -> String {
        if status == 401 {
            return "OneDrive health check failed: the access token is invalid or expired (HTTP 401). Paste a fresh token in the plan editor."
        }
        return "OneDrive health check failed: HTTP \(status). \(response.bodySnippet)"
    }

    private static let pathAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private func accessToken() throws -> String {
        guard let data = keychain.load(account: config.secretRef),
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw DestinationError(
                "OneDrive access token is missing from the Keychain. Paste a fresh token for this destination."
            )
        }
        return token
    }

    private func send(_ request: CloudHTTPRequest, context: String) async throws -> CloudHTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch {
            throw DestinationError("\(context) failed: \(error.localizedDescription). OneDrive may be unreachable.")
        }
    }
}
