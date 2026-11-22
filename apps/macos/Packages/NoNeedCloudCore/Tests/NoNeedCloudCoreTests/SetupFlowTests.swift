import Foundation
import Testing
@testable import NoNeedCloudCore

@MainActor
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
        flow.addSourceFolder(TestSupport.folder("/Users/test/Documents"))
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
        flow.addSourceFolder(TestSupport.folder("/tmp/src"))
        flow.next()
        flow.next()
        #expect(flow.step == .destination)
    }

    @Test func destinationAllowsAdvancingToStartStep() {
        let flow = SetupFlow()
        flow.addSourceFolder(TestSupport.folder("/tmp/src"))
        flow.next()
        flow.destination = TestSupport.folder("/tmp/dest")
        flow.next()
        #expect(flow.step == .startBackup)
    }

    @Test func backReturnsToPreviousStep() {
        let flow = SetupFlow()
        flow.addSourceFolder(TestSupport.folder("/tmp/src"))
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
        flow.addSourceFolder(TestSupport.folder("/tmp/src"))
        flow.next()
        flow.destination = TestSupport.folder("/tmp/dest")
        flow.next()
        #expect(!flow.next())
        #expect(flow.step == .startBackup)
    }

    @Test func duplicateSourceFolderIgnored() {
        let flow = SetupFlow()
        let folder = TestSupport.folder("/tmp/src")
        flow.addSourceFolder(folder)
        flow.addSourceFolder(folder)
        #expect(flow.sourceFolders == [folder])
    }

    @Test func removeSourceFolderUpdatesContinuation() {
        let flow = SetupFlow()
        let folder = TestSupport.folder("/tmp/src")
        flow.addSourceFolder(folder)
        flow.removeSourceFolder(folder)
        #expect(flow.sourceFolders.isEmpty)
        #expect(!flow.canContinue)
    }

    @Test func makePlanReturnsNilUntilSelectionsComplete() {
        let flow = SetupFlow()
        #expect(flow.makePlan() == nil)
        flow.addSourceFolder(TestSupport.folder("/tmp/src"))
        flow.next()
        #expect(flow.makePlan() == nil)
    }

    @Test func makePlanCapturesSelections() {
        let flow = SetupFlow()
        let source = TestSupport.folder("/tmp/src")
        let destination = TestSupport.folder("/tmp/dest")
        flow.addSourceFolder(source)
        flow.includePhotos = true
        flow.destination = destination
        flow.next()
        flow.next()

        let plan = flow.makePlan()
        #expect(plan?.name == SetupFlow.defaultPlanName)
        #expect(plan?.sourceFolders == [source])
        #expect(plan?.includePhotos == true)
        #expect(plan?.destination == destination)
        #expect(plan?.schedule == .manual)
    }
}
