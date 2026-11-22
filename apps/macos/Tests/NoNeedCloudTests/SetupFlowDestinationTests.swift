import Foundation
import Testing
@testable import NoNeedCloud

struct SetupFlowDestinationTests {
    private func makeS3Flow(keychain: MockKeychainStore) -> SetupFlow {
        let flow = SetupFlow()
        flow.keychain = keychain
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        flow.destinationProvider = .s3
        flow.s3Endpoint = "https://minio.local:9000"
        flow.s3Region = "eu-central-1"
        flow.s3Bucket = "mybucket"
        flow.s3Prefix = "backups"
        flow.s3AccessKeyID = "AKID"
        flow.s3SecretAccessKey = "s3cr3t"
        flow.s3UsePathStyle = true
        return flow
    }

    @Test func s3DestinationCapturedInPlanWithSecretInKeychainOnly() throws {
        let keychain = MockKeychainStore()
        let flow = makeS3Flow(keychain: keychain)

        let plan = flow.makePlan()

        guard case .s3(let config) = plan?.destination else {
            Issue.record("expected s3 destination")
            return
        }
        #expect(config.bucket == "mybucket")
        #expect(config.region == "eu-central-1")
        #expect(config.accessKeyID == "AKID")
        #expect(config.endpointURL?.absoluteString == "https://minio.local:9000")
        #expect(config.usePathStyle)
        #expect(!config.secretRef.isEmpty)

        let stored = try #require(try keychain.load(account: config.secretRef))
        let payload = try JSONDecoder().decode(S3SecretPayload.self, from: stored)
        #expect(payload.secretAccessKey == "s3cr3t")
        #expect(payload.sessionToken == nil)

        let planJSON = String(data: try JSONEncoder().encode(plan), encoding: .utf8)!
        #expect(!planJSON.contains("s3cr3t"))
    }

    @Test func s3WithoutSecretDoesNotAllowContinuing() {
        let flow = makeS3Flow(keychain: MockKeychainStore())
        flow.s3SecretAccessKey = ""
        #expect(flow.plannedDestination == nil)
        #expect(!flow.canContinue)
        #expect(flow.makePlan() == nil)
    }

    @Test func s3SessionTokenIsStoredWithSecret() throws {
        let keychain = MockKeychainStore()
        let flow = makeS3Flow(keychain: keychain)
        flow.s3SessionToken = "SESSION-TOK"

        let plan = flow.makePlan()
        guard case .s3(let s3config) = plan?.destination else {
            Issue.record("expected s3 destination")
            return
        }
        let stored = try #require(try keychain.load(account: s3config.secretRef))
        let payload = try JSONDecoder().decode(S3SecretPayload.self, from: stored)
        #expect(payload.sessionToken == "SESSION-TOK")
    }

    @Test func oneDriveTokenCapturedInPlanAndKeychain() throws {
        let keychain = MockKeychainStore()
        let flow = SetupFlow()
        flow.keychain = keychain
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationProvider = .onedrive
        flow.cloudToken = "od-token"

        let plan = flow.makePlan()

        guard case .onedrive(let config) = plan?.destination else {
            Issue.record("expected onedrive destination")
            return
        }
        #expect(!config.secretRef.isEmpty)
        try #expect(keychain.load(account: config.secretRef) == Data("od-token".utf8))
    }

    @Test func googleDriveTokenCapturedInPlanAndKeychain() throws {
        let keychain = MockKeychainStore()
        let flow = SetupFlow()
        flow.keychain = keychain
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationProvider = .gdrive
        flow.cloudToken = "gd-token"

        let plan = flow.makePlan()

        guard case .gdrive(let config) = plan?.destination else {
            Issue.record("expected gdrive destination")
            return
        }
        #expect(!config.secretRef.isEmpty)
        try #expect(keychain.load(account: config.secretRef) == Data("gd-token".utf8))
    }

    @Test func editingCloudPlanKeepsExistingSecretRefWithoutRewritingKeychain() {
        let keychain = MockKeychainStore()
        let flow = SetupFlow()
        flow.keychain = keychain
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationProvider = .onedrive
        flow.existingDestination = .onedrive(CloudTokenConfig(secretRef: "existing-ref"))

        #expect(flow.plannedDestination == .onedrive(CloudTokenConfig(secretRef: "existing-ref")))
        let plan = flow.makePlan()
        #expect(plan?.destination == .onedrive(CloudTokenConfig(secretRef: "existing-ref")))
        #expect(keychain.saveCount == 0)
    }

    @Test func reTypedSecretOverwritesSameKeychainReference() throws {
        let keychain = MockKeychainStore()
        let flow = SetupFlow()
        flow.keychain = keychain
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationProvider = .onedrive
        flow.existingDestination = .onedrive(CloudTokenConfig(secretRef: "existing-ref"))
        flow.cloudToken = "fresh-token"

        let plan = flow.makePlan()
        #expect(plan?.destination == .onedrive(CloudTokenConfig(secretRef: "existing-ref")))
        try #expect(keychain.load(account: "existing-ref") == Data("fresh-token".utf8))
    }

    @Test func folderProviderStillUsesDestinationURL() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")
        #expect(flow.plannedDestination == .folder(URL(fileURLWithPath: "/tmp/dest")))
        let plan = flow.makePlan()
        #expect(plan?.destination == .folder(URL(fileURLWithPath: "/tmp/dest")))
        #expect(plan?.destinationURL == URL(fileURLWithPath: "/tmp/dest"))
    }

    @Test func destinationBuildsCorrectAdapters() throws {
        let keychain = MockKeychainStore()
        let client = FakeHTTPClient()
        let folder = Destination.folder(URL(fileURLWithPath: "/tmp/dest"))
        #expect(folder.makeDestination(keychain: keychain, httpClient: client) is LocalFolderDestination)
        let s3 = Destination.s3(S3Config(
            endpointURL: nil, region: "us-east-1", bucket: "b", prefix: "",
            usePathStyle: true, accessKeyID: "a", secretRef: "r"
        ))
        #expect(s3.makeDestination(keychain: keychain, httpClient: client) is S3Destination)
        let od = Destination.onedrive(CloudTokenConfig(secretRef: "r"))
        #expect(od.makeDestination(keychain: keychain, httpClient: client) is OneDriveDestination)
        let gd = Destination.gdrive(CloudTokenConfig(secretRef: "r"))
        #expect(gd.makeDestination(keychain: keychain, httpClient: client) is GoogleDriveDestination)
    }
}
