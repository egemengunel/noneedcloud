import Foundation

/// S3-compatible destination (AWS S3, MinIO, Wasabi, …). Single-part PUT with
/// header-based SigV4; incremental state lives in the local index only.
final class S3Destination: BackupDestination {
    let config: S3Config
    private let keychain: any KeychainStore
    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    init(config: S3Config, keychain: any KeychainStore, httpClient: any HTTPClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.config = config
        self.keychain = keychain
        self.httpClient = httpClient
        self.now = now
    }

    var label: String { "S3: \(config.bucket)" }

    func healthCheck() async throws {
        _ = try credentials()
        let response = try await send(headBucketRequest(), context: "S3 health check")
        switch response.status {
        case 200...299:
            return
        case 401, 403:
            throw DestinationError(
                "S3 health check failed: access denied (HTTP \(response.status)). "
                    + "Check the access key ID, secret key, and bucket permissions."
            )
        case 404:
            throw DestinationError("S3 health check failed: bucket \"\(config.bucket)\" does not exist (HTTP 404).")
        default:
            throw DestinationError("S3 health check failed: HTTP \(response.status). \(response.bodySnippet)")
        }
    }

    func ensureDirectory(relPath: String) async throws {}

    func copyFile(relPath: String, fromFile: URL, sourceModificationDate: Date, isCancelled: @escaping @Sendable () -> Bool) async throws {
        let credentials = try credentials()
        let key = Self.objectKey(prefix: config.prefix, relPath: relPath)
        guard let uri = Self.requestURI(key: key, config: config) else {
            throw DestinationError("S3 upload failed for \"\(relPath)\": the endpoint URL is invalid.")
        }
        let signer = S3SigV4Signer(
            accessKeyID: config.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            region: config.region,
            sessionToken: credentials.sessionToken
        )
        let signed = signer.sign(
            method: "PUT",
            canonicalURI: uri.canonicalPath,
            host: uri.host,
            extraHeaders: ["Content-Type": "application/octet-stream"],
            payloadHash: S3SigV4Signer.unsignedPayloadHash,
            date: now()
        )
        let request = CloudHTTPRequest(
            method: "PUT",
            url: uri.url,
            headers: signed.headers,
            bodyFileURL: fromFile
        )
        let response = try await send(request, context: "S3 upload of \"\(relPath)\"")
        guard response.isSuccess else {
            throw DestinationError("S3 upload failed for \"\(relPath)\": HTTP \(response.status). \(response.bodySnippet)")
        }
    }

    func destinationFileExists(relPath: String) -> Bool { false }

    // MARK: - Pure mapping helpers

    static func objectKey(prefix: String, relPath: String) -> String {
        let normalizedPrefix = prefix.split(separator: "/").joined(separator: "/")
        let normalizedRel = relPath.split(separator: "/").joined(separator: "/")
        guard !normalizedPrefix.isEmpty else { return normalizedRel }
        return normalizedPrefix + "/" + normalizedRel
    }

    struct RequestURI: Sendable {
        var url: URL
        var canonicalPath: String
        var host: String
    }

    static func requestURI(key: String, config: S3Config) -> RequestURI? {
        objectURI(endpoint: config.effectiveEndpoint, bucket: config.bucket, path: key, usePathStyle: config.usePathStyle)
    }

    static func bucketURI(config: S3Config) -> RequestURI? {
        objectURI(endpoint: config.effectiveEndpoint, bucket: config.bucket, path: "", usePathStyle: config.usePathStyle)
    }

    private static func objectURI(endpoint: URL, bucket: String, path: String, usePathStyle: Bool) -> RequestURI? {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        let encodedPath = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { s3URIEncode(String($0), encodeSlash: false) }
            .joined(separator: "/")
        let bucketSegment = s3URIEncode(bucket, encodeSlash: false)
        let joinedPath = usePathStyle
            ? [bucketSegment, encodedPath].filter { !$0.isEmpty }.joined(separator: "/")
            : encodedPath
        let canonicalPath = "/" + joinedPath
        if !usePathStyle {
            guard let host = components.host else { return nil }
            components.host = "\(bucketSegment).\(host)"
        }
        components.percentEncodedPath = canonicalPath
        guard let url = components.url else { return nil }
        var signingHost = components.host ?? ""
        if let port = components.port, !isDefaultPort(port, scheme: components.scheme) {
            signingHost += ":\(port)"
        }
        return RequestURI(url: url, canonicalPath: canonicalPath, host: signingHost)
    }

    private static func isDefaultPort(_ port: Int, scheme: String?) -> Bool {
        switch (scheme?.lowercased(), port) {
        case ("https", 443), ("http", 80): true
        default: false
        }
    }

    // MARK: - Internals

    private func headBucketRequest() throws -> CloudHTTPRequest {
        let credentials = try credentials()
        guard let uri = Self.bucketURI(config: config) else {
            throw DestinationError("S3 health check failed: the endpoint URL is invalid.")
        }
        let signer = S3SigV4Signer(
            accessKeyID: config.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            region: config.region,
            sessionToken: credentials.sessionToken
        )
        let signed = signer.sign(
            method: "HEAD",
            canonicalURI: uri.canonicalPath,
            host: uri.host,
            payloadHash: S3SigV4Signer.emptyPayloadHash,
            date: now()
        )
        return CloudHTTPRequest(method: "HEAD", url: uri.url, headers: signed.headers)
    }

    private func credentials() throws -> (secretAccessKey: String, sessionToken: String?) {
        guard let data = try keychain.load(account: config.secretRef) else {
            throw DestinationError(
                "S3 credentials are missing from the Keychain. Re-enter the secret access key for this destination."
            )
        }
        if let payload = try? JSONDecoder().decode(S3SecretPayload.self, from: data), !payload.secretAccessKey.isEmpty {
            return (payload.secretAccessKey, payload.sessionToken)
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return (raw, nil)
        }
        throw DestinationError("S3 credentials stored in the Keychain are unreadable. Re-enter the secret access key.")
    }

    private func send(_ request: CloudHTTPRequest, context: String) async throws -> CloudHTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch {
            throw DestinationError("\(context) failed: \(error.localizedDescription). The destination may be unreachable.")
        }
    }
}
