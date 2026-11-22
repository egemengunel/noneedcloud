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

    /// Brings the main window forward, optionally on the History screen.
    func showMainWindow(history: Bool = false, openWindow: OpenWindowAction) {
        openWindow(id: WindowID.main)
        NSApp.activate()
        withAnimation(.smooth(duration: 0.3)) { showsHistory = history }
    }
}
