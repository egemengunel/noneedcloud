import Foundation
import Testing
@testable import NoNeedCloud

private final class MockLoginItemService: LoginItemService {
    enum MockError: Error { case registrationFailed }

    private(set) var enabled = false
    var shouldFail = false

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw MockError.registrationFailed }
        self.enabled = enabled
    }
}

struct LoginItemTests {
    @Test @MainActor func toggleRoundTripsThroughService() throws {
        try TestSupport.withTempStore { store, _ in
            let service = MockLoginItemService()
            let model = AppModel(store: store, loginItem: service)

            #expect(!model.startAtLogin)
            model.setStartAtLogin(true)
            #expect(model.startAtLogin)
            #expect(service.isEnabled())
            model.setStartAtLogin(false)
            #expect(!model.startAtLogin)
            #expect(!service.isEnabled())
            #expect(model.loginItemError == nil)
        }
    }

    @Test @MainActor func failedToggleReportsErrorAndKeepsState() throws {
        try TestSupport.withTempStore { store, _ in
            let service = MockLoginItemService()
            service.shouldFail = true
            let model = AppModel(store: store, loginItem: service)

            model.setStartAtLogin(true)
            #expect(!model.startAtLogin)
            #expect(model.loginItemError != nil)
        }
    }

    @Test @MainActor func missingServiceKeepsToggleUnavailable() throws {
        try TestSupport.withTempStore { store, _ in
            let model = AppModel(store: store)
            #expect(model.loginItem == nil)
            model.setStartAtLogin(true)
            #expect(!model.startAtLogin)
        }
    }

    @Test @MainActor func initialStateReflectsServiceStatus() throws {
        try TestSupport.withTempStore { store, _ in
            let service = MockLoginItemService()
            try service.setEnabled(true)
            let model = AppModel(store: store, loginItem: service)
            #expect(model.startAtLogin)
        }
    }
}
