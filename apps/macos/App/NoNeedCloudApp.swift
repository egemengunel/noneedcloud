import AppKit
import NoNeedCloudCore
import SwiftUI

@main
struct NoNeedCloudApp: App {
    @State private var model = AppModel(
        store: JSONPlanStore.makeDefault(),
        engine: NoNeedCloudApp.makeEngine(),
        healthCheck: { plan in
            let details = plan.destination.flatMap(DestinationHealth.inspect)
            return HealthSnapshot(
                destinationAvailable: plan.destination == nil || details != nil,
                photosAccessGranted: PhotosAccess.isGranted,
                destination: details
            )
        },
        loginItem: .mainApp
    )

    @State private var router = AppRouter()
    @State private var statusItem: StatusItemController?
    @State private var scheduleTicker: ScheduleTicker?

    /// The real engine. A debug build can still demo the UI without touching
    /// files: launch with `NNC_SIMULATED_ENGINE=1`.
    private static func makeEngine() -> any BackupEngine {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NNC_SIMULATED_ENGINE"] == "1" {
            return SimulatedBackupEngine()
        }
        #endif
        return LiveBackupEngine()
    }

    var body: some Scene {
        Window("NoNeedCloud", id: WindowID.main) {
            MainWindowView(model: model)
                .environment(router)
                .frame(minWidth: 960, minHeight: 600)
                .task {
                    if statusItem == nil {
                        statusItem = StatusItemController(model: model, router: router)
                    }
                    if scheduleTicker == nil {
                        scheduleTicker = ScheduleTicker(model: model)
                    }
                    #if DEBUG
                    SnapshotRenderer.runIfRequested()
                    #endif
                    await model.refreshHealth()
                }
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
                OpenHistoryButton(router: router)
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

enum WindowID {
    static let main = "main"
}

private struct OpenHistoryButton: View {
    let router: AppRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Backup History") { router.showMainWindow(history: true, openWindow: openWindow) }
            .keyboardShortcut("y", modifiers: [.command])
    }
}
