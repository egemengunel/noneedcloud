import Foundation

enum PhotoComponentKind: String, Codable, Equatable, Sendable, CaseIterable {
    case original
    case edited
    case livePhotoMovie
    case rawSidecar
}

struct PhotoComponent: Equatable, Hashable, Sendable {
    var kind: PhotoComponentKind
    var filename: String
    var byteSize: Int64?

    var fingerprint: PhotoComponentFingerprint {
        PhotoComponentFingerprint(kind: kind.rawValue, filename: filename, byteSize: byteSize)
    }
}

struct PhotoAsset: Equatable, Sendable {
    var localIdentifier: String
    var filename: String
    var creationDate: Date?
    var modificationDate: Date?
    var isPhoto: Bool
    var isVideo: Bool
    var isFavorite: Bool
    var hasEdits: Bool
    var isLivePhoto: Bool
    var isRawPair: Bool
    var isShared: Bool

    init(
        localIdentifier: String,
        filename: String,
        creationDate: Date?,
        modificationDate: Date?,
        isPhoto: Bool,
        isVideo: Bool,
        isFavorite: Bool = false,
        hasEdits: Bool = false,
        isLivePhoto: Bool = false,
        isRawPair: Bool = false,
        isShared: Bool = false
    ) {
        self.localIdentifier = localIdentifier
        self.filename = filename
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isPhoto = isPhoto
        self.isVideo = isVideo
        self.isFavorite = isFavorite
        self.hasEdits = hasEdits
        self.isLivePhoto = isLivePhoto
        self.isRawPair = isRawPair
        self.isShared = isShared
    }
}

enum PhotoSourceError: LocalizedError {
    case accessDenied
    case componentUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo library access was denied."
        case .componentUnavailable(let name):
            return "Photo component is unavailable: \(name)."
        }
    }
}

protocol PhotoLibrarySource: AnyObject, Sendable {
    func enumerateAssets(includingShared: Bool) async throws -> [PhotoAsset]
    func components(for asset: PhotoAsset) async throws -> [PhotoComponent]
    @discardableResult
    func export(component: PhotoComponent, of asset: PhotoAsset, to destination: URL) async throws -> Int64
}
