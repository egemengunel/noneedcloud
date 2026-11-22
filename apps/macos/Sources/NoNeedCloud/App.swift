import SwiftUI

@main
struct NoNeedCloudApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel(store: JSONPlanStore.makeDefault()))
    }

    var body: some Scene {
        WindowGroup("NoNeedCloud") {
            RootView(model: model)
                .frame(minWidth: 620, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isSetupNeeded {
            SetupWizardView { model.finishSetup($0) }
        } else {
            AtAGlanceView(model: model)
        }
    }
}
