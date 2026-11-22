import AppKit
import NoNeedCloudCore
import SwiftUI

@main
struct NoNeedCloudApp: App {
    @State private var model = AppModel(
        store: JSONPlanStore.makeDefault(),
        // The real copy engine replaces this in M2.
        engine: SimulatedBackupEngine(),
        healthCheck: { plan in
            HealthSnapshot(
                destinationAvailable: plan.destination.map(DestinationHealth.isAvailable) ?? true,
                photosAccessGranted: PhotosAccess.isGranted
            )
        }
    )

    var body: some Scene {
        Window("NoNeedCloud", id: WindowID.main) {
            MainWindowView(model: model)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 640, idealHeight: 700)
                .task { await model.refreshHealth() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.refreshHealth() }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowArrangement) {
                OpenHistoryButton()
            }
        }

        Window("Backup History", id: WindowID.history) {
            HistoryView(model: model)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 620, height: 460)
    }
}

enum WindowID {
    static let main = "main"
    static let history = "history"
}

private struct OpenHistoryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Backup History") { openWindow(id: WindowID.history) }
            .keyboardShortcut("y", modifiers: [.command])
    }
}
