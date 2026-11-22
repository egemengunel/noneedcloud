import Foundation
import Testing
@testable import NoNeedCloud

struct CloudDestinationTests {
    private func makeS3Destination(
        httpClient: FakeHTTPClient,
        keychain: MockKeychainStore = MockKeychainStore(),
        config: S3Config? = nil
    ) -> S3Destination {
        if let config {
            return S3Destination(config: config, keychain: keychain, httpClient: httpClient)
        }
        return S3Destination(
            config: S3Config(
                endpointURL: URL(string: "https://minio.local:9000"),
                region: "us-east-1",
                bucket: "mybucket",
                prefix: "backups",
                usePathStyle: true,
                accessKeyID: "AKID",
                secretRef: "ref-1"
            ),
            keychain: keychain,
            httpClient: httpClient
        )
    }

    private func storeS3Secret(_ keychain: MockKeychainStore, sessionToken: String? = nil) throws {
        let payload = S3SecretPayload(secretAccessKey: "s3cr3t", sessionToken: sessionToken)
        try keychain.save(Data(JSONEncoder().encode(payload)), account: "ref-1")
    }

    // MARK: - S3

    @Test func s3HealthCheckFailureMapsStatusToReason() async throws {
        let keychain = MockKeychainStore()
        try storeS3Secret(keychain)
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 403, data: Data()) })
        let destination = makeS3Destination(httpClient: client, keychain: keychain)
        do {
            try await destination.healthCheck()
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("403"))
            #expect(error.message.contains("access denied"))
        }
        let request = client.requests.first
        #expect(request?.method == "HEAD")
        #expect(request?.url.path == "/mybucket")
        #expect(request?.headers["Authorization"]?.hasPrefix("AWS4-HMAC-SHA256 ") == true)
        #expect(request?.headers["x-amz-date"]?.isEmpty == false)
    }

    @Test func s3HealthCheckMapsUnreachableErrors() async throws {
        let keychain = MockKeychainStore()
        try storeS3Secret(keychain)
        let client = FakeHTTPClient(responder: { _ in
            throw URLError(.cannotFindHost)
        })
        let destination = makeS3Destination(httpClient: client, keychain: keychain)
        do {
            try await destination.healthCheck()
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("unreachable"))
        }
    }

    @Test func s3MissingKeychainSecretFailsBeforeAnyRequest() async throws {
        let client = FakeHTTPClient()
        let destination = makeS3Destination(httpClient: client)
        do {
            try await destination.healthCheck()
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("Keychain"))
            #expect(client.requests.isEmpty)
        }
    }

    @Test func s3CopyFilePutsFileWithSignedHeaders() async throws {
        let keychain = MockKeychainStore()
        try storeS3Secret(keychain, sessionToken: "SESSION")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 200, data: Data()) })
        let destination = makeS3Destination(httpClient: client, keychain: keychain)

        let source = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("input.txt")
        try Data("hello".utf8).write(to: file)

        try await destination.copyFile(relPath: "Docs/a b.txt", fromFile: file, sourceModificationDate: Date(), isCancelled: { false })

        let request = try #require(client.requests.first)
        #expect(request.method == "PUT")
        #expect(request.url.absoluteString == "https://minio.local:9000/mybucket/backups/Docs/a%20b.txt")
        #expect(request.bodyFileURL == file)
        #expect(request.headers["x-amz-security-token"] == "SESSION")
        #expect(request.headers["Authorization"]?.contains("x-amz-security-token") == true)
        #expect(request.headers["x-amz-content-sha256"] == S3SigV4Signer.unsignedPayloadHash)
    }

    @Test func s3CopyFileSurfacesHTTPStatusWithRelPath() async throws {
        let keychain = MockKeychainStore()
        try storeS3Secret(keychain)
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 500, data: Data("boom".utf8)) })
        let destination = makeS3Destination(httpClient: client, keychain: keychain)
        do {
            try await destination.copyFile(relPath: "Docs/a.txt", fromFile: URL(fileURLWithPath: "/dev/null"), sourceModificationDate: Date(), isCancelled: { false })
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("Docs/a.txt"))
            #expect(error.message.contains("500"))
        }
    }

    // MARK: - OneDrive

    private func makeOneDriveDestination(client: FakeHTTPClient, keychain: MockKeychainStore) -> OneDriveDestination {
        OneDriveDestination(config: CloudTokenConfig(secretRef: "od-ref"), keychain: keychain, httpClient: client)
    }

    @Test func oneDriveHealthCheckUsesGraphMe() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("token-1".utf8), account: "od-ref")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 200, data: Data("{}".utf8)) })
        let destination = makeOneDriveDestination(client: client, keychain: keychain)

        try await destination.healthCheck()

        let request = try #require(client.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://graph.microsoft.com/v1.0/me")
        #expect(request.headers["Authorization"] == "Bearer token-1")
    }

    @Test func oneDriveExpiredTokenProducesClearReason() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("expired".utf8), account: "od-ref")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 401, data: Data()) })
        let destination = makeOneDriveDestination(client: client, keychain: keychain)
        do {
            try await destination.healthCheck()
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("401"))
            #expect(error.message.contains("token"))
        }
    }

    @Test func oneDriveCopyFilePutsToRootPathContent() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("token-1".utf8), account: "od-ref")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 201, data: Data("{}".utf8)) })
        let destination = makeOneDriveDestination(client: client, keychain: keychain)

        let source = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("input.txt")
        try Data("hello".utf8).write(to: file)

        try await destination.copyFile(relPath: "Docs/2024/a b.txt", fromFile: file, sourceModificationDate: Date(), isCancelled: { false })

        let request = try #require(client.requests.first)
        #expect(request.method == "PUT")
        #expect(request.url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/Docs/2024/a%20b.txt:/content")
        #expect(request.bodyFileURL == file)
        #expect(request.headers["Authorization"] == "Bearer token-1")
    }

    // MARK: - Google Drive

    private func makeGoogleDriveDestination(client: FakeHTTPClient, keychain: MockKeychainStore) -> GoogleDriveDestination {
        GoogleDriveDestination(config: CloudTokenConfig(secretRef: "gd-ref"), keychain: keychain, httpClient: client)
    }

    private func driveResponder(folderId: String) -> @Sendable (CloudHTTPRequest) throws -> CloudHTTPResponse {
        { request in
            if request.method == "GET", request.url.path == "/drive/v3/files" {
                return CloudHTTPResponse(status: 200, data: Data("{\"files\": []}".utf8))
            }
            if request.method == "POST", request.url.path == "/drive/v3/files" {
                return CloudHTTPResponse(status: 200, data: Data("{\"id\": \"\(folderId)\"}".utf8))
            }
            if request.url.path == "/upload/drive/v3/files" {
                return CloudHTTPResponse(status: 200, data: Data("{\"id\": \"file-1\"}".utf8))
            }
            return CloudHTTPResponse(status: 404, data: Data())
        }
    }

    @Test func googleDriveCopyFileCreatesFoldersStepwiseThenUploadsMultipart() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("token-1".utf8), account: "gd-ref")
        let client = FakeHTTPClient(responder: driveResponder(folderId: "fold-2"))
        let destination = makeGoogleDriveDestination(client: client, keychain: keychain)

        let source = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("input.txt")
        try Data("hello".utf8).write(to: file)

        try await destination.copyFile(relPath: "Docs/Sub/a.txt", fromFile: file, sourceModificationDate: Date(), isCancelled: { false })

        // Stepwise folder resolution for Docs and Docs/Sub, then the upload.
        #expect(client.requests.count == 5)
        let lookups = client.requests.filter { $0.method == "GET" }
        let creates = client.requests.filter { $0.method == "POST" && $0.url.path == "/drive/v3/files" }
        let upload = try #require(client.requests.last)
        #expect(lookups.count == 2)
        #expect(creates.count == 2)
        #expect(upload.url.absoluteString == "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")
        #expect(upload.headers["Content-Type"]?.contains("multipart/related") == true)

        let bodyFileURL = try #require(upload.bodyFileURL)
        #expect(!FileManager.default.fileExists(atPath: bodyFileURL.path), "multipart temp file must be removed")
        let body = String(data: recordedBody(try #require(client.requests.last), in: client), encoding: .utf8)
        #expect(body?.contains("\"name\":\"a.txt\"") == true)
        #expect(body?.contains("hello") == true)
    }

    private func recordedBody(_ request: CloudHTTPRequest, in client: FakeHTTPClient) -> Data {
        client.recordedBodies.last ?? Data()
    }

    @Test func googleDriveReusesResolvedFoldersAcrossFiles() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("token-1".utf8), account: "gd-ref")
        let client = FakeHTTPClient(responder: driveResponder(folderId: "fold-2"))
        let destination = makeGoogleDriveDestination(client: client, keychain: keychain)

        let source = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("input.txt")
        try Data("hello".utf8).write(to: file)

        try await destination.copyFile(relPath: "Docs/Sub/a.txt", fromFile: file, sourceModificationDate: Date(), isCancelled: { false })
        try await destination.copyFile(relPath: "Docs/Sub/b.txt", fromFile: file, sourceModificationDate: Date(), isCancelled: { false })

        #expect(client.requests.count == 6, "second upload in the same folder must only add one request")
        #expect(client.requests.last?.url.absoluteString.contains("uploadType=multipart") == true)
    }

    @Test func googleDriveExpiredTokenProducesClearReason() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("expired".utf8), account: "gd-ref")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 401, data: Data()) })
        let destination = makeGoogleDriveDestination(client: client, keychain: keychain)
        do {
            try await destination.healthCheck()
            Issue.record("expected failure")
        } catch let error as DestinationError {
            #expect(error.message.contains("401"))
            #expect(error.message.contains("token"))
        }
    }

    @Test func googleDriveHealthCheckUsesAboutEndpoint() async throws {
        let keychain = MockKeychainStore()
        try keychain.save(Data("token-1".utf8), account: "gd-ref")
        let client = FakeHTTPClient(responder: { _ in CloudHTTPResponse(status: 200, data: Data("{}".utf8)) })
        let destination = makeGoogleDriveDestination(client: client, keychain: keychain)

        try await destination.healthCheck()

        let request = try #require(client.requests.first)
        #expect(request.url.host == "www.googleapis.com")
        #expect(request.url.path == "/drive/v3/about")
        #expect(request.headers["Authorization"] == "Bearer token-1")
    }
}
