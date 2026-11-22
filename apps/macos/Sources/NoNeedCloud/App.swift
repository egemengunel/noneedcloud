import SwiftUI

@main
struct NoNeedCloudApp: App {
    @StateObject private var model: AppModel
    @State private var scheduleRunner: ScheduleRunner?

    init() {
        let model = AppModel(store: JSONPlanStore.makeDefault(), loginItem: SMLoginItemService())
        _model = StateObject(wrappedValue: model)
        AppModelAccess.shared = model
        scheduleRunner = ScheduleRunner(scheduler: model)
    }

    var body: some Scene {
        WindowGroup("NoNeedCloud", id: "main") {
            RootView(model: model)
                .frame(minWidth: 620, minHeight: 440)
                .task { scheduleRunner?.start() }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(model: model)
                .task { scheduleRunner?.start() }
        } label: {
            MenuBarIcon(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isSetupNeeded {
            SetupWizardView(
                onStartBackup: { plan in
                    model.finishSetup(plan)
                    model.startBackup(plan)
                },
                keychain: model.keychain
            )
        } else {
            AtAGlanceView(model: model)
        }
    }
}
