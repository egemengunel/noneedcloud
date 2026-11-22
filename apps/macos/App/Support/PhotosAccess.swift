import AppKit
import Photos

enum PhotosAccess {
    /// true = granted (full or limited), false = denied/restricted, nil = not asked yet.
    static var isGranted: Bool? {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        case .denied, .restricted: false
        case .notDetermined: nil
        @unknown default: nil
        }
    }

    static func request() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    @MainActor
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}
