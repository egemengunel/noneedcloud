import Foundation

/// Turns "Start NoNeedCloud at login" on and off. `mainApp` uses
/// `SMAppService`; tests pass closures.
public struct LoginItemControl: Sendable {
    public var isEnabled: @Sendable () -> Bool
    public var setEnabled: @Sendable (Bool) throws -> Void

    public init(isEnabled: @escaping @Sendable () -> Bool, setEnabled: @escaping @Sendable (Bool) throws -> Void) {
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
    }

    public static var mainApp: LoginItemControl {
        let service = SMLoginItemService()
        return LoginItemControl(isEnabled: { service.isEnabled() }, setEnabled: { try service.setEnabled($0) })
    }
}
