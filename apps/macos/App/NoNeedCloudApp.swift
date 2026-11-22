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
            let details = plan.destination.flatMap(DestinationHealth.inspect)
            return HealthSnapshot(
                destinationAvailable: plan.destination == nil || details != nil,
                photosAccessGranted: PhotosAccess.isGranted,
                destination: details
            )
        }
    )

    var body: some Scene {
        Window("NoNeedCloud", id: WindowID.main) {
            MainWindowView(model: model)
                .frame(minWidth: 960, minHeight: 600)
                .task { await model.refreshHealth() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.refreshHealth() }
                }
        }
        .defaultSize(width: 1000, height: 650)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Show Welcome Screen") {
                    NotificationCenter.default.post(name: .showWelcome, object: nil)
                }
            }
            CommandGroup(after: .windowArrangement) {
                OpenHistoryButton()
            }
        }

        Window("Backup History", id: WindowID.history) {
            HistoryView(model: model)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 620, height: 460)

        Settings {
            SettingsView(model: model)
        }
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
