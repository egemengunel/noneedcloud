import Foundation
import ServiceManagement

protocol LoginItemService: AnyObject {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

/// Thin wrapper around SMAppService for the app's own login item.
final class SMLoginItemService: LoginItemService {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
