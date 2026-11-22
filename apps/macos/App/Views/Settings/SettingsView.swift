import NoNeedCloudCore
import SwiftUI

/// The app's Settings window (gear button in the toolbar, ⌘,).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("Schedule", systemImage: "calendar.badge.clock") {
                SchedulePopover(model: model)
                    .frame(width: 440)
            }
            Tab("Photos", systemImage: "photo.on.rectangle.angled") {
                Form {
                    Toggle("Photos", isOn: model.planBinding(\.photos.includePhotos))
                    Toggle("Videos", isOn: model.planBinding(\.photos.includeVideos))
                    Toggle("Edited versions alongside originals", isOn: model.planBinding(\.photos.includeEdits))
                    Toggle("Shared Albums", isOn: model.planBinding(\.photos.includeSharedAlbums))
                    Section("Mirroring") {
                        MirroringPopover(model: model)
                    }
                }
                .formStyle(.grouped)
                .disabled(!model.plan.photos.isEnabled)
                .frame(width: 440)
            }
        }
        .scenePadding()
    }
}
