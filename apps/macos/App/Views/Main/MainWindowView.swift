import AppKit
import NoNeedCloudCore
import SwiftUI

/// The one main window. Shows the welcome screen on first launch, then the
/// screen for the current `MainScreenState` (Figma scenarios 01–04).
struct MainWindowView: View {
    /// What the window shows at each launch: loading screen → onboarding → the app.
    enum LaunchPhase { case loading, onboarding, app }

    let model: AppModel
    /// Every launch starts at `.loading`; nothing is persisted, so onboarding shows each time.
    @State private var phase: LaunchPhase
    @State private var activeSheet: SetupSheet?

    init(model: AppModel, startingAt phase: LaunchPhase = .loading) {
        self.model = model
        _phase = State(initialValue: phase)
    }

    private var showsWelcome: Bool { phase != .app }

    var body: some View {
        Group {
            if phase == .loading {
                LaunchView()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .task {
                        // Show the loading screen at least briefly, and until health is known.
                        async let health: Void = model.refreshHealth()
                        try? await Task.sleep(for: .seconds(1.6))
                        await health
                        withAnimation(.smooth(duration: 0.45)) { phase = .onboarding }
                    }
            } else if phase == .onboarding {
                WelcomeView(isReturning: model.lastCompletedRun != nil) {
                    withAnimation(.smooth(duration: 0.35)) { phase = .app }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                content
                    .padding(.horizontal, 27)
                    .padding(.top, 23)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.window)
                    .transition(.opacity)
            }
        }
        .toolbar { toolbarContent }
        .toolbar(removing: .title)
        .toolbarBackground(Theme.window, for: .windowToolbar)
        // Launch and onboarding art runs under a transparent toolbar.
        .toolbarBackgroundVisibility(showsWelcome ? .hidden : .automatic, for: .windowToolbar)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .photos: PhotosSettingsSheet(model: model, actions: actions)
            case .folders: SourceFoldersSheet(model: model)
            case .destination: DestinationSheet(model: model)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.screenState)
        .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in
            withAnimation { phase = .onboarding }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screenState {
        case let .setup(reached):
            SetupFlowView(model: model, reached: reached, actions: actions)
                .padding(.horizontal, -4)
        case .running:
            if let progress = model.progress {
                RunningView(model: model, progress: progress)
            }
        case .protected:
            ProtectedView(model: model, actions: actions)
        case let .needsAttention(issue):
            AttentionView(model: model, issue: issue, actions: actions)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        AppTitleToolbarItem(onDark: showsWelcome)

        if !showsWelcome {
            TrailingToolbarSpacer()
            ToolbarItemGroup(placement: .automatic) {
                if model.screenState.setupStep != nil {
                    AboutSetupButton()
                } else {
                    HistoryToolbarButton()
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
    }

    private var actions: SetupActions {
        SetupActions(model: model, showSheet: { activeSheet = $0 })
    }
}

/// Brand cloud + name at the leading edge of the toolbar. On macOS 26 the
/// item's glass capsule is hidden so it reads as a title, like the design.
private struct AppTitleToolbarItem: ToolbarContent {
    let onDark: Bool

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { title }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { title }
        }
    }

    private var title: some View {
        HStack(spacing: 10) {
            BrandCloud(color: onDark ? Theme.lightBlue : Theme.ink, width: 24)
            Text(verbatim: "NoNeedCloud")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(onDark ? .white : Theme.ink)
        }
        .padding(.horizontal, 4)
    }
}

/// Pushes the following items to the trailing edge on macOS 26, where
/// toolbar items otherwise pack next to the title.
private struct TrailingToolbarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        }
    }
}

extension Notification.Name {
    static let showWelcome = Notification.Name("NoNeedCloud.showWelcome")
}

enum SetupSheet: String, Identifiable {
    case photos, folders, destination
    var id: String { rawValue }
}

/// The setup actions shared by the setup flow and the status screens.
@MainActor
struct SetupActions {
    let model: AppModel
    let showSheet: (SetupSheet) -> Void

    /// Asks for Photos access if needed, then turns the Photos source on.
    func enablePhotos() {
        Task {
            let granted: Bool
            if let known = PhotosAccess.isGranted {
                granted = known
            } else {
                granted = await PhotosAccess.request()
            }
            if granted {
                model.updatePlan { $0.photos.isEnabled = true }
            } else {
                PhotosAccess.openPrivacySettings()
            }
            await model.refreshHealth()
        }
    }

    func chooseFolders() {
        let folders = FolderPicker.chooseFolders(message: String(localized: "Choose the folders you want to protect."), prompt: String(localized: "Add"))
        if !folders.isEmpty { model.addFolders(folders) }
    }

    func chooseDestination() {
        if let destination = FolderPicker.chooseDestination() {
            model.setDestination(destination)
        }
    }

    /// Network shares must be mounted first (Finder → Go → Connect to Server, ⌘K).
    func chooseNetworkDestination() {
        if let destination = FolderPicker.chooseDestination(
            startingAt: URL(fileURLWithPath: "/Volumes"),
            message: String(localized: "Choose a folder on your network drive. If it isn't listed, connect to it in Finder first (Go → Connect to Server).")
        ) {
            model.setDestination(destination)
        }
    }
}

private struct HistoryToolbarButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowID.history)
        } label: {
            Label("History", systemImage: "clock")
                .labelStyle(.titleAndIcon)
        }
        .help("Show backup history")
    }
}

private struct AboutSetupButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Label("About Setup", systemImage: "info.circle")
        }
        .help("About setup")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Three steps to your first backup")
                    .font(.headline)
                Text("Pick what to protect, choose where to keep it, then review and start. You can change everything later.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}
