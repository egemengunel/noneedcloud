import AppKit
import Observation
import SwiftUI

/// Which screen the main window shows besides the backup status, shared by
/// the main window, the menu bar extra and the menu commands.
@MainActor
@Observable
final class AppRouter {
    /// History is shown inside the main window, not in a window of its own.
    var showsHistory = false

    /// SwiftUI scene actions, captured from the main window so AppKit code
    /// (the menu bar panel) can reopen the window or Settings.
    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored var openSettings: (() -> Void)?

    /// Brings the main window forward, optionally on the History screen.
    func showMainWindow(history: Bool = false, openWindow: OpenWindowAction? = nil) {
        if let action = openWindow ?? self.openWindow {
            action(id: WindowID.main)
        } else {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        withAnimation(.smooth(duration: 0.3)) { showsHistory = history }
    }
}
