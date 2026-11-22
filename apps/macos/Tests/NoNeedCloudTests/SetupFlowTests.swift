import Foundation
import Testing
@testable import NoNeedCloud

struct SetupFlowTests {
    @Test func initialStateIsSourcesStep() {
        let flow = SetupFlow()
        #expect(flow.step == .sources)
        #expect(!flow.canContinue)
    }

    @Test func cannotAdvanceWithoutAnySource() {
        let flow = SetupFlow()
        flow.next()
        #expect(flow.step == .sources)
    }

    @Test func folderSourceAllowsAdvancingToDestination() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/Users/test/Documents"))
        #expect(flow.canContinue)
        #expect(flow.next())
        #expect(flow.step == .destination)
    }

    @Test func photosToggleAllowsAdvancingToDestination() {
        let flow = SetupFlow()
        flow.includePhotos = true
        #expect(flow.next())
        #expect(flow.step == .destination)
    }

    @Test func destinationRequiredBeforeStartStep() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        flow.next()
        #expect(flow.step == .destination)
    }

    @Test func destinationAllowsAdvancingToStartStep() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")
        flow.next()
        #expect(flow.step == .startBackup)
    }

    @Test func backReturnsToPreviousStep() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        flow.back()
        #expect(flow.step == .sources)
    }

    @Test func backOnFirstStepDoesNothing() {
        let flow = SetupFlow()
        #expect(!flow.back())
        #expect(flow.step == .sources)
    }

    @Test func nextOnFinalStepDoesNothing() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")
        flow.next()
        #expect(!flow.next())
        #expect(flow.step == .startBackup)
    }

    @Test func duplicateSourceFolderIgnored() {
        let flow = SetupFlow()
        let url = URL(fileURLWithPath: "/tmp/src")
        flow.addSourceFolder(url)
        flow.addSourceFolder(url)
        #expect(flow.sourceFolderURLs == [url])
    }

    @Test func removeSourceFolderUpdatesContinuation() {
        let flow = SetupFlow()
        let url = URL(fileURLWithPath: "/tmp/src")
        flow.addSourceFolder(url)
        flow.removeSourceFolder(url)
        #expect(flow.sourceFolderURLs.isEmpty)
        #expect(!flow.canContinue)
    }

    @Test func makePlanReturnsNilUntilSelectionsComplete() {
        let flow = SetupFlow()
        #expect(flow.makePlan() == nil)
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.next()
        #expect(flow.makePlan() == nil)
    }

    @Test func makePlanCapturesSelections() {
        let flow = SetupFlow()
        let source = URL(fileURLWithPath: "/tmp/src")
        let destination = URL(fileURLWithPath: "/tmp/dest")
        flow.addSourceFolder(source)
        flow.includePhotos = true
        flow.destinationURL = destination
        flow.next()
        flow.next()

        let plan = flow.makePlan()
        #expect(plan?.name == SetupFlow.defaultPlanName)
        #expect(plan?.sourceFolderURLs == [source])
        #expect(plan?.includePhotos == true)
        #expect(plan?.destinationURL == destination)
        #expect(plan?.schedule == .manual)
    }

    @Test func makePlanCapturesMirroringSelections() {
        let flow = SetupFlow()
        flow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")
        flow.mirrorEnabled = true
        flow.mirrorRetention = .untilNextBackup

        let plan = flow.makePlan()
        #expect(plan?.mirrorOptions == MirrorOptions(enabled: true, retention: .untilNextBackup))

        let offFlow = SetupFlow()
        offFlow.addSourceFolder(URL(fileURLWithPath: "/tmp/src"))
        offFlow.destinationURL = URL(fileURLWithPath: "/tmp/dest")
        #expect(offFlow.makePlan()?.mirrorOptions == .disabled)
    }

    @Test func iCloudDriveToggleAloneAllowsAdvancingAndIsCapturedInPlan() {
        let flow = SetupFlow()
        flow.includeICloudDrive = true
        #expect(flow.canContinue)
        #expect(flow.next())
        #expect(flow.step == .destination)
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")

        let plan = flow.makePlan()
        #expect(plan?.sources == [.icloudDrive])
    }

    @Test func appContainerTogglesAloneAllowAdvancing() {
        let flow = SetupFlow()
        flow.includePages = true
        #expect(flow.canContinue)
        flow.includePages = false
        flow.includeNumbers = true
        #expect(flow.canContinue)
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")

        let plan = flow.makePlan()
        #expect(plan?.sources == [.numbers])
    }

    @Test func iCloudTogglesCombineWithFoldersInStableOrder() {
        let flow = SetupFlow()
        let folder = URL(fileURLWithPath: "/tmp/src")
        flow.addSourceFolder(folder)
        flow.includeNumbers = true
        flow.includeICloudDrive = true
        flow.includePages = true

        #expect(flow.plannedSources == [.folder(folder), .icloudDrive, .pages, .numbers])
    }

    @Test func turningEverySourceOffBlocksContinuationAndPlan() {
        let flow = SetupFlow()
        flow.includeICloudDrive = true
        flow.includeICloudDrive = false
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")

        #expect(!flow.canContinue)
        #expect(flow.makePlan() == nil)
    }

    @Test func iCloudSourceNamesAppearInSummary() {
        let flow = SetupFlow()
        flow.includeICloudDrive = true
        flow.includePages = true
        #expect(flow.plannedSources.map(\.displayName) == ["iCloud Drive", "Pages"])
    }
}
