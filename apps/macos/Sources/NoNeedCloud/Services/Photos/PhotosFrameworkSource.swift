@preconcurrency import Photos

final class PhotosFrameworkSource: PhotoLibrarySource, @unchecked Sendable {
    func enumerateAssets(includingShared: Bool) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var assets: [PhotoAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            assets.append(Self.photoAsset(from: asset, isShared: false))
        }
        if includingShared {
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
                .enumerateObjects { collection, _, _ in
                    PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
                        assets.append(Self.photoAsset(from: asset, isShared: true))
                    }
                }
        }
        return assets
    }

    func components(for asset: PhotoAsset) async throws -> [PhotoComponent] {
        guard let libraryAsset = Self.fetchAsset(identifier: asset.localIdentifier) else {
            throw PhotoSourceError.componentUnavailable(asset.filename)
        }
        return PHAssetResource.assetResources(for: libraryAsset).compactMap(Self.asComponent)
    }

    @discardableResult
    func export(component: PhotoComponent, of asset: PhotoAsset, to destination: URL) async throws -> Int64 {
        guard let libraryAsset = Self.fetchAsset(identifier: asset.localIdentifier) else {
            throw PhotoSourceError.componentUnavailable(component.filename)
        }
        let resources = PHAssetResource.assetResources(for: libraryAsset)
        guard let resource = Self.resource(matching: component, in: resources) else {
            throw PhotoSourceError.componentUnavailable(component.filename)
        }
        let temporaryURL = URL(fileURLWithPath: destination.path + ".tmp")
        try? FileManager.default.removeItem(at: temporaryURL)
        do {
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { continuation in
                PHAssetResourceManager.default().writeData(
                    for: resource,
                    toFile: temporaryURL,
                    options: options
                ) { error in
                    continuation.resume(with: error.map { .failure($0) } ?? .success(()))
                }
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            }
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return Int64(size)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func ensureAuthorized() async throws {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else { throw PhotoSourceError.accessDenied }
        default:
            throw PhotoSourceError.accessDenied
        }
    }

    private static func fetchAsset(identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private static func photoAsset(from asset: PHAsset, isShared: Bool) -> PhotoAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == .photo } ?? resources.first { $0.type == .video }
        return PhotoAsset(
            localIdentifier: asset.localIdentifier,
            filename: primary?.originalFilename ?? asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            isPhoto: asset.mediaType == .image,
            isVideo: asset.mediaType == .video,
            isFavorite: asset.isFavorite,
            hasEdits: resources.contains { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo },
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isRawPair: resources.contains { $0.type == .alternatePhoto },
            isShared: isShared
        )
    }

    private static func asComponent(_ resource: PHAssetResource) -> PhotoComponent? {
        let kind: PhotoComponentKind
        switch resource.type {
        case .photo, .video:
            kind = .original
        case .fullSizePhoto, .fullSizeVideo:
            kind = .edited
        case .pairedVideo, .fullSizePairedVideo:
            kind = .livePhotoMovie
        case .alternatePhoto:
            kind = .rawSidecar
        default:
            return nil
        }
        return PhotoComponent(
            kind: kind,
            filename: resource.originalFilename,
            byteSize: resource.value(forKey: "fileSize") as? Int64
        )
    }

    private static func resource(matching component: PhotoComponent, in resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { asComponent($0) == component }
    }
}
