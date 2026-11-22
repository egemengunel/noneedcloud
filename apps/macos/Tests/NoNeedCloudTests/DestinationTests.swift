import Foundation
import Testing
@testable import NoNeedCloud

struct DestinationModelTests {
    private func makeS3Config(
        endpoint: URL? = URL(string: "https://minio.local:9000"),
        region: String = "us-east-1",
        bucket: String = "mybucket",
        prefix: String = "backups",
        usePathStyle: Bool = true,
        accessKeyID: String = "AKID",
        secretRef: String = "ref-1"
    ) -> S3Config {
        S3Config(
            endpointURL: endpoint,
            region: region,
            bucket: bucket,
            prefix: prefix,
            usePathStyle: usePathStyle,
            accessKeyID: accessKeyID,
            secretRef: secretRef
        )
    }

    // MARK: - Codable

    @Test func legacyPlanJSONWithDestinationURLDecodesAsFolderDestination() throws {
        let json = """
        {
            "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
            "name": "Legacy",
            "sources": [{"kind": "folder", "url": "file:///tmp/src"}],
            "includePhotos": false,
            "photoOptions": {},
            "destinationURL": "file:///tmp/dest"
        }
        """
        let plan = try JSONDecoder().decode(BackupPlan.self, from: Data(json.utf8))
        #expect(plan.destination == .folder(URL(fileURLWithPath: "/tmp/dest")))
        #expect(plan.destinationURL == URL(fileURLWithPath: "/tmp/dest"))
    }

    @Test func malformedDestinationDataThrowsItsOwnErrorNotLegacyFallback() {
        let json = """
        {
            "id": "6B29FC40-CA47-1067-B31D-00DD010662DA",
            "name": "Broken",
            "sources": [{"kind": "folder", "url": "file:///tmp/src"}],
            "includePhotos": false,
            "photoOptions": {},
            "destination": {"kind": "bogus"}
        }
        """
        do {
            _ = try JSONDecoder().decode(BackupPlan.self, from: Data(json.utf8))
            Issue.record("expected failure")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("bogus"))
            #expect(!message.contains("destinationURL"))
        }
    }

    @Test func destinationRoundTripsForAllProviders() throws {
        let destinations: [Destination] = [
            .folder(URL(fileURLWithPath: "/tmp/dest")),
            .s3(makeS3Config()),
            .onedrive(CloudTokenConfig(secretRef: "od-ref")),
            .gdrive(CloudTokenConfig(secretRef: "gd-ref")),
        ]
        for destination in destinations {
            let plan = TestSupport.makePlan(destination: destination)
            let data = try JSONEncoder().encode(plan)
            let decoded = try JSONDecoder().decode(BackupPlan.self, from: data)
            #expect(decoded.destination == destination)
        }
    }

    @Test func encodedS3PlanContainsNoSecret() throws {
        let plan = TestSupport.makePlan(destination: .s3(makeS3Config()))
        let json = String(data: try JSONEncoder().encode(plan), encoding: .utf8)!
        #expect(!json.contains("s3cr3t"))
        #expect(json.contains("secretRef"))
    }

    // MARK: - Labels and index keys

    @Test func displayNamePerProvider() {
        #expect(Destination.folder(URL(fileURLWithPath: "/tmp/dest")).displayName == "/tmp/dest")
        #expect(Destination.s3(makeS3Config()).displayName.contains("mybucket"))
        #expect(Destination.onedrive(CloudTokenConfig(secretRef: "r")).displayName == "OneDrive")
        #expect(Destination.gdrive(CloudTokenConfig(secretRef: "r")).displayName == "Google Drive")
    }

    @Test func indexKeysAreStablePerDestinationIdentity() {
        let folder = Destination.folder(URL(fileURLWithPath: "/tmp/dest"))
        #expect(folder.indexKey == "/tmp/dest")
        #expect(folder.indexKey == URL(fileURLWithPath: "/tmp/dest").path(percentEncoded: false))

        let s3 = Destination.s3(makeS3Config())
        #expect(s3.indexKey.contains("minio.local"))
        #expect(s3.indexKey.contains("mybucket"))
        #expect(s3.indexKey.contains("backups"))
        #expect(s3.indexKey != Destination.s3(makeS3Config(bucket: "other")).indexKey)
        #expect(s3.indexKey != Destination.s3(makeS3Config(prefix: "")).indexKey)

        #expect(Destination.onedrive(CloudTokenConfig(secretRef: "a")).indexKey == "onedrive/a")
        #expect(Destination.onedrive(CloudTokenConfig(secretRef: "a")).indexKey != Destination.onedrive(CloudTokenConfig(secretRef: "b")).indexKey)
        #expect(Destination.gdrive(CloudTokenConfig(secretRef: "a")).indexKey == "gdrive/a")
        #expect(Destination.gdrive(CloudTokenConfig(secretRef: "a")).indexKey != Destination.gdrive(CloudTokenConfig(secretRef: "b")).indexKey)
        #expect(Destination.onedrive(CloudTokenConfig(secretRef: "r")).indexKey != Destination.gdrive(CloudTokenConfig(secretRef: "r")).indexKey)
        #expect(Destination.s3(makeS3Config()).indexKey != Destination.onedrive(CloudTokenConfig(secretRef: "r")).indexKey)
    }

    @Test func indexFileURLDiffersPerDestinationKind() {
        let state = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: state) }
        let source = BackupSource.folder(URL(fileURLWithPath: "/tmp/src"))
        let folderIndex = IncrementalIndex.indexFileURL(stateDirectory: state, destination: .folder(URL(fileURLWithPath: "/tmp/dest")), source: source)
        let s3Index = IncrementalIndex.indexFileURL(stateDirectory: state, destination: .s3(makeS3Config()), source: source)
        #expect(folderIndex != s3Index)
        #expect(
            folderIndex == IncrementalIndex.indexFileURL(
                stateDirectory: state,
                destination: URL(fileURLWithPath: "/tmp/dest"),
                source: source
            )
        )
    }

    /// Two accounts of the same provider must never share incremental state:
    /// a shared index would make the second account look fully backed-up.
    @Test func cloudDestinationIndexFileURLsDifferPerAccount() {
        let state = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: state) }
        let source = BackupSource.folder(URL(fileURLWithPath: "/tmp/src"))

        let oneDriveAccountA = IncrementalIndex.indexFileURL(
            stateDirectory: state,
            destination: .onedrive(CloudTokenConfig(secretRef: "account-a")),
            source: source
        )
        let oneDriveAccountB = IncrementalIndex.indexFileURL(
            stateDirectory: state,
            destination: .onedrive(CloudTokenConfig(secretRef: "account-b")),
            source: source
        )
        #expect(oneDriveAccountA != oneDriveAccountB)
        #expect(
            oneDriveAccountA == IncrementalIndex.indexFileURL(
                stateDirectory: state,
                destination: .onedrive(CloudTokenConfig(secretRef: "account-a")),
                source: source
            )
        )

        let gdriveAccountA = IncrementalIndex.indexFileURL(
            stateDirectory: state,
            destination: .gdrive(CloudTokenConfig(secretRef: "account-a")),
            source: source
        )
        let gdriveAccountB = IncrementalIndex.indexFileURL(
            stateDirectory: state,
            destination: .gdrive(CloudTokenConfig(secretRef: "account-b")),
            source: source
        )
        #expect(gdriveAccountA != gdriveAccountB)
        #expect(gdriveAccountA != oneDriveAccountA)
    }

    // MARK: - S3 mapping

    @Test func s3ObjectKeyJoinsPrefixAndRelPath() {
        #expect(S3Destination.objectKey(prefix: "backups", relPath: "Pages/2024/a.txt") == "backups/Pages/2024/a.txt")
        #expect(S3Destination.objectKey(prefix: "", relPath: "Pages/a.txt") == "Pages/a.txt")
        #expect(S3Destination.objectKey(prefix: "/leading/", relPath: "a.txt") == "leading/a.txt")
        #expect(S3Destination.objectKey(prefix: "a//b", relPath: "c.txt") == "a/b/c.txt")
    }

    @Test func s3RequestURIPathStyleWithCustomEndpointAndPort() throws {
        let uri = try #require(S3Destination.requestURI(key: "backups/Pages/a b+c.txt", config: makeS3Config()))
        #expect(uri.url.absoluteString == "https://minio.local:9000/mybucket/backups/Pages/a%20b%2Bc.txt")
        #expect(uri.canonicalPath == "/mybucket/backups/Pages/a%20b%2Bc.txt")
        #expect(uri.host == "minio.local:9000")
    }

    @Test func s3RequestURIVirtualHostedStyleOnAWS() throws {
        let config = makeS3Config(endpoint: nil, usePathStyle: false)
        let uri = try #require(S3Destination.requestURI(key: "Pages/a.txt", config: config))
        #expect(uri.url.absoluteString == "https://mybucket.s3.us-east-1.amazonaws.com/Pages/a.txt")
        #expect(uri.canonicalPath == "/Pages/a.txt")
        #expect(uri.host == "mybucket.s3.us-east-1.amazonaws.com")
    }

    @Test func s3RequestURIDefaultPortOmittedFromHost() throws {
        let config = makeS3Config(endpoint: URL(string: "https://minio.local"), usePathStyle: true)
        let uri = try #require(S3Destination.requestURI(key: "a.txt", config: config))
        #expect(uri.host == "minio.local")
        #expect(uri.url.absoluteString == "https://minio.local/mybucket/a.txt")
    }

    // MARK: - OneDrive mapping

    @Test func oneDriveObjectPathEncodesEachSegmentButKeepsSlashes() {
        #expect(OneDriveDestination.encodedObjectPath("Pages/2024/a b.txt") == "Pages/2024/a%20b.txt")
        #expect(OneDriveDestination.encodedObjectPath("C#report/x?y.txt") == "C%23report/x%3Fy.txt")
        #expect(OneDriveDestination.encodedObjectPath("/leading/") == "leading")
    }

    // MARK: - Google Drive mapping

    @Test func googleDriveParentAndNameSplit() {
        #expect(GoogleDriveDestination.parentDirectory(of: "Pages/2024/a.txt") == "Pages/2024")
        #expect(GoogleDriveDestination.parentDirectory(of: "a.txt") == "")
        #expect(GoogleDriveDestination.lastComponent(of: "Pages/2024/a.txt") == "a.txt")
        #expect(GoogleDriveDestination.lastComponent(of: "a.txt") == "a.txt")
    }

    @Test func googleDriveMultipartBodyConcatenatesMetadataAndMedia() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("media.bin")
        try Data("media-bytes".utf8).write(to: media)

        let boundary = "BOUNDARY"
        let bodyURL = try GoogleDriveDestination.writeMultipartBody(
            metadata: Data(#"{"name":"a.txt","parents":["fold1"]}"#.utf8),
            fileURL: media,
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let body = try #require(String(data: try Data(contentsOf: bodyURL), encoding: .utf8))
        #expect(body.contains("--BOUNDARY\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"))
        #expect(body.contains(#"{"name":"a.txt","parents":["fold1"]}"#))
        #expect(body.contains("\r\n--BOUNDARY\r\nContent-Type: application/octet-stream\r\n\r\n"))
        #expect(body.contains("media-bytes"))
        #expect(body.hasSuffix("\r\n--BOUNDARY--\r\n"))
    }
}
