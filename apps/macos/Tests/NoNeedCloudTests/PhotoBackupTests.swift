import Foundation
import Testing
@testable import NoNeedCloud

enum PhotoTestClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static let runDay = date(2026, 11, 22)
}

final class MockPhotoLibrarySource: PhotoLibrarySource, @unchecked Sendable {
    private let lock = NSLock()
    private var dataByAsset: [String: [PhotoComponent: Data]] = [:]
    private(set) var assets: [PhotoAsset]
    private(set) var events: [String] = []
    private(set) var mutationCount = 0
    private(set) var factorySharesSeen = false
    var failExport = false
    var failComponents: Set<PhotoComponentKind> = []

    init(assets: [PhotoAsset] = []) {
        self.assets = assets
    }

    func addData(assetId: String, component: PhotoComponent, _ data: Data) {
        lock.withLock {
            dataByAsset[assetId, default: [:]][component] = data
        }
    }

    func mutateLibrary() {
        lock.withLock { mutationCount += 1 }
    }

    func snapshotData() -> [String: [PhotoComponent: Data]] {
        lock.withLock { dataByAsset }
    }

    func enumerateAssets(includingShared: Bool) async throws -> [PhotoAsset] {
        lock.withLock { factorySharesSeen = includingShared }
        record("enumerate shared=\(includingShared)")
        return assets.filter { includingShared || !$0.isShared }
    }

    func components(for asset: PhotoAsset) async throws -> [PhotoComponent] {
        record("components \(asset.localIdentifier)")
        let components = lock.withLock { dataByAsset[asset.localIdentifier]?.map(\.key) } ?? []
        return components.sorted {
            $0.filename == $1.filename ? $0.kind.rawValue < $1.kind.rawValue : $0.filename < $1.filename
        }
    }

    @discardableResult
    func export(component: PhotoComponent, of asset: PhotoAsset, to destination: URL) async throws -> Int64 {
        record("start \(asset.localIdentifier) \(component.kind.rawValue)")
        await Task.yield()
        if failExport || failComponents.contains(component.kind) {
            throw PhotoSourceError.componentUnavailable(component.filename)
        }
        let data = lock.withLock { dataByAsset[asset.localIdentifier]?[component] }
        guard let data else {
            throw PhotoSourceError.componentUnavailable(component.filename)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
        record("end \(asset.localIdentifier) \(component.kind.rawValue)")
        return Int64(data.count)
    }

    private func record(_ event: String) {
        lock.withLock { events.append(event) }
    }
}

enum PhotoTestFixtures {
    static func asset(
        id: String,
        filename: String,
        creation: Date?,
        modification: Date? = nil,
        isPhoto: Bool = true,
        isVideo: Bool = false,
        hasEdits: Bool = false,
        isLivePhoto: Bool = false,
        isRawPair: Bool = false,
        isShared: Bool = false
    ) -> PhotoAsset {
        PhotoAsset(
            localIdentifier: id,
            filename: filename,
            creationDate: creation,
            modificationDate: modification,
            isPhoto: isPhoto,
            isVideo: isVideo,
            hasEdits: hasEdits,
            isLivePhoto: isLivePhoto,
            isRawPair: isRawPair,
            isShared: isShared
        )
    }

    static func component(_ kind: PhotoComponentKind, _ filename: String, size: Int64) -> PhotoComponent {
        PhotoComponent(kind: kind, filename: filename, byteSize: size)
    }
}

struct PhotoLayoutTests {
    @Test func dayFolderPrefersCreationDate() {
        let asset = PhotoTestFixtures.asset(id: "a", filename: "x.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        #expect(PhotoLayout.relativeDayPath(for: asset, today: PhotoTestClock.runDay, calendar: PhotoTestClock.calendar) == "2024/07/15")
    }

    @Test func dayFolderFallsBackToModificationDate() {
        let asset = PhotoTestFixtures.asset(id: "a", filename: "x.jpg", creation: nil, modification: PhotoTestClock.date(2021, 3, 4))
        #expect(PhotoLayout.relativeDayPath(for: asset, today: PhotoTestClock.runDay, calendar: PhotoTestClock.calendar) == "2021/03/04")
    }

    @Test func dayFolderFallsBackToToday() {
        let asset = PhotoTestFixtures.asset(id: "a", filename: "x.jpg", creation: nil, modification: nil)
        #expect(PhotoLayout.relativeDayPath(for: asset, today: PhotoTestClock.runDay, calendar: PhotoTestClock.calendar) == "2026/11/22")
    }

    @Test func uniqueFileNameKeepsFirstCandidateAndSuffixesCollisions() {
        #expect(PhotoLayout.uniqueFileName(candidate: "IMG.jpg", usedNames: []) == "IMG.jpg")
        #expect(PhotoLayout.uniqueFileName(candidate: "IMG.jpg", usedNames: ["img.jpg"]) == "IMG-1.jpg")
        #expect(PhotoLayout.uniqueFileName(candidate: "IMG.jpg", usedNames: ["img.jpg", "img-1.jpg"]) == "IMG-2.jpg")
        #expect(PhotoLayout.uniqueFileName(candidate: "MOV", usedNames: ["mov"]) == "MOV-1")
    }
}

struct PhotoFilterTests {
    private let options = PhotoOptions()

    @Test func fullTimelineKeepsEverything() {
        let assets = [
            PhotoTestFixtures.asset(id: "p", filename: "p.jpg", creation: nil, isPhoto: true),
            PhotoTestFixtures.asset(id: "v", filename: "v.mov", creation: nil, isPhoto: false, isVideo: true),
        ]
        #expect(PhotoAssetFilter.select(assets, options: PhotoOptions()).count == 2)
    }

    @Test func photosOnlyAndVideosOnlyRestrict() {
        let photo = PhotoTestFixtures.asset(id: "p", filename: "p.jpg", creation: nil, isPhoto: true)
        let video = PhotoTestFixtures.asset(id: "v", filename: "v.mov", creation: nil, isPhoto: false, isVideo: true)
        #expect(PhotoAssetFilter.select([photo, video], options: PhotoOptions(photosOnly: true)) == [photo])
        #expect(PhotoAssetFilter.select([photo, video], options: PhotoOptions(videosOnly: true)) == [video])
        #expect(PhotoAssetFilter.select([photo, video], options: PhotoOptions(photosOnly: true, videosOnly: true)).isEmpty)
    }

    @Test func dateRangeIsInclusiveOnBothEnds() {
        let old = PhotoTestFixtures.asset(id: "o", filename: "o.jpg", creation: PhotoTestClock.date(2019, 6, 1))
        let inRangeStart = PhotoTestFixtures.asset(id: "s", filename: "s.jpg", creation: PhotoTestClock.date(2024, 1, 1, hour: 0))
        let inRangeEnd = PhotoTestFixtures.asset(id: "e", filename: "e.jpg", creation: PhotoTestClock.date(2024, 12, 31, hour: 23))
        let late = PhotoTestFixtures.asset(id: "l", filename: "l.jpg", creation: PhotoTestClock.date(2025, 2, 2))
        let options = PhotoOptions(dateRangeStart: PhotoTestClock.date(2024, 1, 1, hour: 0), dateRangeEnd: PhotoTestClock.date(2024, 12, 31))
        let selected = PhotoAssetFilter.select([old, inRangeStart, inRangeEnd, late], options: options, calendar: PhotoTestClock.calendar)
        #expect(selected == [inRangeStart, inRangeEnd])
    }

    @Test func selectedComponentsGateExtrasBehindIncludeEdits() {
        let asset = PhotoTestFixtures.asset(
            id: "a",
            filename: "IMG.jpg",
            creation: nil,
            hasEdits: true,
            isLivePhoto: true,
            isRawPair: true
        )
        let components = [
            PhotoTestFixtures.component(.original, "IMG.jpg", size: 10),
            PhotoTestFixtures.component(.edited, "IMG_edited.heic", size: 20),
            PhotoTestFixtures.component(.livePhotoMovie, "IMG.mov", size: 30),
            PhotoTestFixtures.component(.rawSidecar, "IMG.dng", size: 40),
        ]
        #expect(PhotoAssetFilter.selectedComponents(components, asset: asset, options: PhotoOptions()).count == 4)
        let plain = PhotoAssetFilter.selectedComponents(components, asset: asset, options: PhotoOptions(includeEdits: false))
        #expect(plain == [components[0]])
        #expect(PhotoAssetFilter.selectedComponents(components, asset: asset, options: PhotoOptions()).contains(components[1]))
    }

    @Test func uneditedAssetExportsOnlyOriginalEvenWithIncludeEdits() {
        let asset = PhotoTestFixtures.asset(id: "a", filename: "IMG.jpg", creation: nil)
        let components = [
            PhotoTestFixtures.component(.original, "IMG.jpg", size: 10),
            PhotoTestFixtures.component(.livePhotoMovie, "IMG.mov", size: 30),
        ]
        #expect(PhotoAssetFilter.selectedComponents(components, asset: asset, options: PhotoOptions()) == [components[0]])
    }
}

struct PhotoOptionsDecodingTests {
    @Test func legacyOptionsJSONDecodesWithDefaults() throws {
        let legacy = Data("{\"fullTimeline\":true}".utf8)
        let options = try JSONDecoder().decode(PhotoOptions.self, from: legacy)
        #expect(options.fullTimeline)
        #expect(!options.photosOnly)
        #expect(!options.videosOnly)
        #expect(options.includeEdits)
        #expect(!options.includeSharedAlbums)
        #expect(options.dateRangeStart == nil)
        #expect(options.dateRangeEnd == nil)
    }

    @Test func optionsRoundTrip() throws {
        let options = PhotoOptions(
            photosOnly: true,
            includeEdits: false,
            includeSharedAlbums: true,
            dateRangeStart: PhotoTestClock.date(2024, 1, 1),
            dateRangeEnd: PhotoTestClock.date(2024, 6, 1)
        )
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(PhotoOptions.self, from: data) == options)
    }
}

struct PhotoIncrementalIndexTests {
    @Test func indexPersistsEntriesAcrossInstances() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.json")

        let writer = PhotoIncrementalIndex(url: url)
        writer.update("asset-1", entry: PhotoIndexEntry(
            modificationDate: 100.5,
            fingerprints: [PhotoComponentFingerprint(kind: "original", filename: "a.jpg", byteSize: 12)],
            paths: ["original": "2024/07/15/a.jpg"]
        ))
        try writer.save()

        let reader = PhotoIncrementalIndex(url: url)
        #expect(reader.entry(for: "asset-1") == PhotoIndexEntry(
            modificationDate: 100.5,
            fingerprints: [PhotoComponentFingerprint(kind: "original", filename: "a.jpg", byteSize: 12)],
            paths: ["original": "2024/07/15/a.jpg"]
        ))
        #expect(reader.entry(for: "missing") == nil)
        #expect(reader.count == 1)
    }

    @Test func corruptIndexFileLoadsAsEmpty() throws {
        let dir = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.json")
        try Data("garbage".utf8).write(to: url)
        #expect(PhotoIncrementalIndex(url: url).count == 0)
    }

    @Test func indexFileURLIsDeterministicPerDestination() {
        let stateDirectory = URL(fileURLWithPath: "/tmp/state")
        let destination = URL(fileURLWithPath: "/tmp/dest")
        let first = PhotoIncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destination)
        let second = PhotoIncrementalIndex.indexFileURL(stateDirectory: stateDirectory, destination: destination)
        #expect(first == second)
        #expect(first.lastPathComponent.hasPrefix("photo-index-"))
    }
}

struct PhotoBackupCoordinatorTests {
    private var calendar: Calendar { PhotoTestClock.calendar }

    private func makeCoordinator(
        source: MockPhotoLibrarySource,
        destination: URL,
        options: PhotoOptions = PhotoOptions(),
        stateURL: URL
    ) -> PhotoBackupCoordinator {
        PhotoBackupCoordinator(
            source: source,
            destinationURL: destination,
            options: options,
            stateURL: stateURL,
            calendar: calendar,
            today: PhotoTestClock.runDay
        )
    }

    private func readData(_ relativePath: String, in root: URL) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    @Test func firstRunExportsFullTimelineInDayFoldersAtOriginalQuality() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = MockPhotoLibrarySource(assets: [
            PhotoTestFixtures.asset(id: "p1", filename: "IMG_0001.jpg", creation: PhotoTestClock.date(2024, 7, 15)),
            PhotoTestFixtures.asset(id: "v1", filename: "VID_0001.mov", creation: PhotoTestClock.date(2023, 1, 2), isPhoto: false, isVideo: true),
        ])
        source.addData(assetId: "p1", component: PhotoTestFixtures.component(.original, "IMG_0001.jpg", size: 6), Data("photo1".utf8))
        source.addData(assetId: "v1", component: PhotoTestFixtures.component(.original, "VID_0001.mov", size: 6), Data("video1".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        let result = await coordinator.run()

        #expect(result.outcome == .completed)
        #expect(result.itemsCopied == 2)
        #expect(result.itemsFailed == 0)
        #expect(result.bytesCopied == 12)
        #expect(result.itemsProtected == 2)
        #expect(try readData("Photos/2024/07/15/IMG_0001.jpg", in: destination) == Data("photo1".utf8))
        #expect(try readData("Photos/2023/01/02/VID_0001.mov", in: destination) == Data("video1".utf8))
    }

    @Test func editedLivePhotoRawAssetExportsAllComponents() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(
            id: "fancy",
            filename: "IMG_0002.jpg",
            creation: PhotoTestClock.date(2024, 7, 15),
            hasEdits: true,
            isLivePhoto: true,
            isRawPair: true
        )
        let original = PhotoTestFixtures.component(.original, "IMG_0002.jpg", size: 4)
        let edited = PhotoTestFixtures.component(.edited, "IMG_0002_edited.heic", size: 5)
        let movie = PhotoTestFixtures.component(.livePhotoMovie, "IMG_0002.mov", size: 6)
        let raw = PhotoTestFixtures.component(.rawSidecar, "IMG_0002.dng", size: 7)
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "fancy", component: original, Data("orig".utf8))
        source.addData(assetId: "fancy", component: edited, Data("edit".utf8))
        source.addData(assetId: "fancy", component: movie, Data("movie".utf8))
        source.addData(assetId: "fancy", component: raw, Data("raws".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        _ = await coordinator.run()

        let folder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)
        #expect(try readData("IMG_0002.jpg", in: folder) == Data("orig".utf8))
        #expect(try readData("IMG_0002_edited.heic", in: folder) == Data("edit".utf8))
        #expect(try readData("IMG_0002.mov", in: folder) == Data("movie".utf8))
        #expect(try readData("IMG_0002.dng", in: folder) == Data("raws".utf8))
    }

    @Test func includeEditsOffExportsOnlyOriginal() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a", filename: "IMG_0003.jpg", creation: PhotoTestClock.date(2024, 7, 15), hasEdits: true, isLivePhoto: true)
        let original = PhotoTestFixtures.component(.original, "IMG_0003.jpg", size: 4)
        let edited = PhotoTestFixtures.component(.edited, "IMG_0003_edited.heic", size: 5)
        let movie = PhotoTestFixtures.component(.livePhotoMovie, "IMG_0003.mov", size: 6)
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a", component: original, Data("orig".utf8))
        source.addData(assetId: "a", component: edited, Data("edit".utf8))
        source.addData(assetId: "a", component: movie, Data("movie".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(
            source: source,
            destination: destination,
            options: PhotoOptions(includeEdits: false),
            stateURL: root.appendingPathComponent("photo.json")
        )

        _ = await coordinator.run()

        let folder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("IMG_0003.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("IMG_0003_edited.heic").path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("IMG_0003.mov").path))
    }

    @Test func collidingAssetNamesAreDisambiguated() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = PhotoTestFixtures.asset(id: "one", filename: "IMG_0004.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let second = PhotoTestFixtures.asset(id: "two", filename: "IMG_0004.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let component = PhotoTestFixtures.component(.original, "IMG_0004.jpg", size: 4)
        let source = MockPhotoLibrarySource(assets: [first, second])
        source.addData(assetId: "one", component: component, Data("aaaa".utf8))
        source.addData(assetId: "two", component: component, Data("bbbb".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        _ = await coordinator.run()

        let folder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)
        #expect(try readData("IMG_0004.jpg", in: folder) == Data("aaaa".utf8))
        #expect(try readData("IMG_0004-1.jpg", in: folder) == Data("bbbb".utf8))
    }

    @Test func existingDestinationFileIsNeverOverwrittenByNewAsset() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let dayFolder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dayFolder.appendingPathComponent("IMG_0005.jpg"))
        let asset = PhotoTestFixtures.asset(id: "new", filename: "IMG_0005.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let component = PhotoTestFixtures.component(.original, "IMG_0005.jpg", size: 4)
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "new", component: component, Data("new!".utf8))
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        _ = await coordinator.run()

        #expect(try readData("IMG_0005.jpg", in: dayFolder) == Data("old".utf8))
        #expect(try readData("IMG_0005-1.jpg", in: dayFolder) == Data("new!".utf8))
    }

    @Test func secondRunSkipsUnchangedAndReExportsEditedAssetsInPlace() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let unchanged = PhotoTestFixtures.asset(id: "keep", filename: "KEEP.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        var editedAsset = PhotoTestFixtures.asset(id: "edit", filename: "EDIT.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let keepComponent = PhotoTestFixtures.component(.original, "KEEP.jpg", size: 4)
        let editComponent = PhotoTestFixtures.component(.original, "EDIT.jpg", size: 4)

        func makeSource() -> MockPhotoLibrarySource {
            let source = MockPhotoLibrarySource(assets: [unchanged, editedAsset])
            source.addData(assetId: "keep", component: keepComponent, Data("keep".utf8))
            source.addData(assetId: "edit", component: editComponent, Data("v1!!".utf8))
            return source
        }

        let first = await makeCoordinator(source: makeSource(), destination: destination, stateURL: root.appendingPathComponent("photo.json")).run()
        #expect(first.itemsCopied == 2)

        let secondSource = makeSource()
        let second = await makeCoordinator(source: secondSource, destination: destination, stateURL: root.appendingPathComponent("photo.json")).run()
        #expect(second.itemsCopied == 0)
        #expect(second.itemsSkipped == 2)

        editedAsset.modificationDate = PhotoTestClock.date(2024, 8, 1)
        let newAsset = PhotoTestFixtures.asset(id: "fresh", filename: "FRESH.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let thirdSource = MockPhotoLibrarySource(assets: [unchanged, editedAsset, newAsset])
        thirdSource.addData(assetId: "keep", component: keepComponent, Data("keep".utf8))
        thirdSource.addData(assetId: "edit", component: editComponent, Data("v2!!".utf8))
        thirdSource.addData(assetId: "fresh", component: PhotoTestFixtures.component(.original, "FRESH.jpg", size: 4), Data("new!".utf8))
        let third = await makeCoordinator(source: thirdSource, destination: destination, stateURL: root.appendingPathComponent("photo.json")).run()

        #expect(third.itemsCopied == 2)
        #expect(third.itemsSkipped == 1)
        let dayFolder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)
        let dayFiles = try FileManager.default.contentsOfDirectory(atPath: dayFolder.path).sorted()
        #expect(dayFiles == ["EDIT.jpg", "FRESH.jpg", "KEEP.jpg"])
        #expect(try readData("EDIT.jpg", in: dayFolder) == Data("v2!!".utf8))
        #expect(!dayFiles.contains("EDIT-1.jpg"))
        #expect(dayFiles.contains("FRESH.jpg"))
    }

    @Test func dateRangeExcludesOutOfRangeAssets() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = PhotoTestFixtures.asset(id: "old", filename: "OLD.jpg", creation: PhotoTestClock.date(2019, 6, 1))
        let recent = PhotoTestFixtures.asset(id: "new", filename: "NEW.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let source = MockPhotoLibrarySource(assets: [old, recent])
        source.addData(assetId: "old", component: PhotoTestFixtures.component(.original, "OLD.jpg", size: 4), Data("old!".utf8))
        source.addData(assetId: "new", component: PhotoTestFixtures.component(.original, "NEW.jpg", size: 4), Data("new!".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(
            source: source,
            destination: destination,
            options: PhotoOptions(dateRangeStart: PhotoTestClock.date(2024, 1, 1), dateRangeEnd: PhotoTestClock.date(2024, 12, 31)),
            stateURL: root.appendingPathComponent("photo.json")
        )

        let result = await coordinator.run()

        #expect(result.itemsCopied == 1)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Photos/2019/06/01").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Photos/2024/07/15/NEW.jpg").path))
    }

    @Test func sharedAlbumAssetsOnlyRunWhenOptedIn() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = PhotoTestFixtures.asset(id: "shared", filename: "SHARED.jpg", creation: PhotoTestClock.date(2024, 7, 15), isShared: true)
        let component = PhotoTestFixtures.component(.original, "SHARED.jpg", size: 4)
        let destination = root.appendingPathComponent("Dest", isDirectory: true)

        let offSource = MockPhotoLibrarySource(assets: [shared])
        offSource.addData(assetId: "shared", component: component, Data("sha!".utf8))
        let off = await makeCoordinator(source: offSource, destination: destination, stateURL: root.appendingPathComponent("photo.json")).run()
        #expect(off.itemsCopied == 0)
        #expect(offSource.events.contains("enumerate shared=false"))

        let onSource = MockPhotoLibrarySource(assets: [shared])
        onSource.addData(assetId: "shared", component: component, Data("sha!".utf8))
        let on = await makeCoordinator(
            source: onSource,
            destination: destination,
            options: PhotoOptions(includeSharedAlbums: true),
            stateURL: root.appendingPathComponent("photo.json")
        ).run()
        #expect(on.itemsCopied == 1)
        #expect(onSource.events.contains("enumerate shared=true"))
    }

    @Test func assetsAreProcessedOneAtATimeInOrder() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = (0..<3).map { index in
            PhotoTestFixtures.asset(id: "a\(index)", filename: "A\(index).jpg", creation: PhotoTestClock.date(2024, 7, 15))
        }
        let source = MockPhotoLibrarySource(assets: assets)
        for index in 0..<3 {
            source.addData(
                assetId: "a\(index)",
                component: PhotoTestFixtures.component(.original, "A\(index).jpg", size: 4),
                Data("data\(index)".utf8)
            )
        }
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        _ = await coordinator.run()

        let exportEvents = source.events.filter { $0.hasPrefix("start") || $0.hasPrefix("end") }
        #expect(exportEvents == [
            "start a0 original", "end a0 original",
            "start a1 original", "end a1 original",
            "start a2 original", "end a2 original",
        ])
    }

    @Test func mockLibraryIsNeverMutatedDuringBackup() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a", filename: "A.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a", component: PhotoTestFixtures.component(.original, "A.jpg", size: 4), Data("data".utf8))
        let snapshot = source.snapshotData()
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        _ = await coordinator.run()
        _ = await coordinator.run()

        #expect(source.mutationCount == 0)
        #expect(source.snapshotData() == snapshot)
        #expect(try readData("Photos/2024/07/15/A.jpg", in: destination) == Data("data".utf8))
    }

    @Test func failedComponentIsRecordedAndAssetIsNotIndexed() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a", filename: "A.jpg", creation: PhotoTestClock.date(2024, 7, 15), hasEdits: true)
        let original = PhotoTestFixtures.component(.original, "A.jpg", size: 4)
        let source = MockPhotoLibrarySource(assets: [asset])
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))

        let missingComponents = await coordinator.run()
        #expect(missingComponents.itemsCopied == 0)
        #expect(missingComponents.itemsFailed == 1)
        #expect(missingComponents.itemsProtected == 0)
        let missingErrors = await coordinator.state.errors
        #expect(missingErrors.count == 1)

        source.addData(assetId: "a", component: original, Data("data".utf8))
        source.failExport = true
        let exportFailure = await coordinator.run()
        #expect(exportFailure.itemsCopied == 0)
        #expect(exportFailure.itemsFailed == 1)
        #expect(exportFailure.itemsProtected == 0)

        source.failExport = false
        let retry = await coordinator.run()
        #expect(retry.outcome == .completed)
        #expect(retry.itemsCopied == 1)
        #expect(retry.itemsProtected == 1)
        #expect(try readData("Photos/2024/07/15/A.jpg", in: destination) == Data("data".utf8))
    }

    @Test func partialExportFailureLeavesNoOrphanAndRetryUsesCanonicalName() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a", filename: "A.jpg", creation: PhotoTestClock.date(2024, 7, 15), hasEdits: true)
        let original = PhotoTestFixtures.component(.original, "A.jpg", size: 4)
        let edited = PhotoTestFixtures.component(.edited, "A_edited.heic", size: 5)
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a", component: original, Data("orig".utf8))
        source.addData(assetId: "a", component: edited, Data("edit".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))
        let dayFolder = destination.appendingPathComponent("Photos/2024/07/15", isDirectory: true)

        source.failComponents = [.edited]
        let first = await coordinator.run()
        #expect(first.itemsCopied == 0)
        #expect(first.itemsFailed == 1)
        let filesAfterFirst = (try? FileManager.default.contentsOfDirectory(atPath: dayFolder.path)) ?? []
        #expect(filesAfterFirst.isEmpty)

        source.failComponents = []
        let second = await coordinator.run()
        #expect(second.outcome == .completed)
        #expect(second.itemsCopied == 1)
        #expect(try readData("A.jpg", in: dayFolder) == Data("orig".utf8))
        #expect(try readData("A_edited.heic", in: dayFolder) == Data("edit".utf8))
        let filesAfterSecond = (try? FileManager.default.contentsOfDirectory(atPath: dayFolder.path).sorted()) ?? []
        #expect(filesAfterSecond == ["A.jpg", "A_edited.heic"])
    }

    @Test func stopBeforeRunProducesCancelledResult() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a", filename: "A.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a", component: PhotoTestFixtures.component(.original, "A.jpg", size: 4), Data("data".utf8))
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let coordinator = makeCoordinator(source: source, destination: destination, stateURL: root.appendingPathComponent("photo.json"))
        coordinator.stop()

        let result = await coordinator.run()

        #expect(result.outcome == .cancelled)
        #expect(result.itemsCopied == 0)
    }
}

final class PhotoSourceBox: @unchecked Sendable {
    let source: MockPhotoLibrarySource
    private let lock = NSLock()
    private(set) var creations = 0

    init(source: MockPhotoLibrarySource) {
        self.source = source
    }

    func make() -> any PhotoLibrarySource {
        lock.withLock { creations += 1 }
        return source
    }
}

@MainActor
struct AppModelPhotoBackupTests {
    @Test func photosOnlyPlanRunsPhotoPassThroughFactory() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = PhotoTestFixtures.asset(id: "a1", filename: "A1.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a1", component: PhotoTestFixtures.component(.original, "A1.jpg", size: 4), Data("data".utf8))
        let box = PhotoSourceBox(source: source)
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(
            store: store,
            runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true),
            photoSourceFactory: { box.make() }
        )
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let plan = TestSupport.makePlan(name: "Photos", sources: [], includePhotos: true, destination: destination)

        let results = await model.backup(plan)

        #expect(box.creations == 1)
        #expect(results.count == 1)
        #expect(results[0].outcome == .completed)
        #expect(results[0].itemsCopied == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Photos/2024/07/15/A1.jpg")) == Data("data".utf8))
        #expect(model.history.count == 1)
        #expect(model.history[0].itemsCopied == 1)
        #expect(model.itemsProtected == 1)
        #expect(model.lastBackupDate != nil)
    }

    @Test func folderAndPhotoResultsAggregateIntoSingleRecord() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folderSource = root.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folderSource, withIntermediateDirectories: true)
        try Data("doc".utf8).write(to: folderSource.appendingPathComponent("doc.txt"))
        let asset = PhotoTestFixtures.asset(id: "a1", filename: "A1.jpg", creation: PhotoTestClock.date(2024, 7, 15))
        let source = MockPhotoLibrarySource(assets: [asset])
        source.addData(assetId: "a1", component: PhotoTestFixtures.component(.original, "A1.jpg", size: 4), Data("data".utf8))
        let box = PhotoSourceBox(source: source)
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(
            store: store,
            runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true),
            photoSourceFactory: { box.make() }
        )
        let destination = root.appendingPathComponent("Dest", isDirectory: true)
        let plan = TestSupport.makePlan(name: "Both", sources: [folderSource], includePhotos: true, destination: destination)

        let results = await model.backup(plan)

        #expect(results.count == 2)
        #expect(model.history.count == 1)
        #expect(model.history[0].itemsCopied == 2)
        #expect(model.history[0].outcome == .completed)
        #expect(model.itemsProtected == 2)
        #expect(try Data(contentsOf: destination.appendingPathComponent("Docs/doc.txt")) == Data("doc".utf8))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Photos/2024/07/15/A1.jpg").path))
    }

    @Test func photoSourceIsNotCreatedWhenPlanExcludesPhotos() async throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let box = PhotoSourceBox(source: MockPhotoLibrarySource())
        let store = JSONPlanStore(directory: root.appendingPathComponent("State", isDirectory: true))
        let model = AppModel(
            store: store,
            runStateDirectory: root.appendingPathComponent("RunState", isDirectory: true),
            photoSourceFactory: { box.make() }
        )
        let plan = TestSupport.makePlan(name: "Folders", sources: [], includePhotos: false)

        _ = await model.backup(plan)

        #expect(box.creations == 0)
        #expect(model.history.isEmpty)
    }

    @Test func photoPassIsStoppedTogetherWithFolderEngines() {
        let model = AppModel(store: JSONPlanStore(directory: TestSupport.makeTempDirectory()))
        model.stopBackup()
        #expect(!model.isBackupRunning)
    }
}

struct SetupFlowPhotoOptionsTests {
    @Test func makePlanCapturesPhotoSelections() {
        let flow = SetupFlow()
        flow.includePhotos = true
        flow.photosOnly = true
        flow.includeSharedAlbums = true
        flow.usePhotoDateRange = true
        flow.photoDateRangeStart = PhotoTestClock.date(2024, 1, 1)
        flow.photoDateRangeEnd = PhotoTestClock.date(2024, 12, 31)
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")

        let plan = flow.makePlan()

        #expect(plan?.includePhotos == true)
        #expect(plan?.photoOptions.photosOnly == true)
        #expect(plan?.photoOptions.videosOnly == false)
        #expect(plan?.photoOptions.includeSharedAlbums == true)
        #expect(plan?.photoOptions.dateRangeStart == PhotoTestClock.date(2024, 1, 1))
        #expect(plan?.photoOptions.dateRangeEnd == PhotoTestClock.date(2024, 12, 31))
    }

    @Test func dateRangeOmittedWhenToggleOff() {
        let flow = SetupFlow()
        flow.includePhotos = true
        flow.photoDateRangeStart = PhotoTestClock.date(2024, 1, 1)
        flow.photoDateRangeEnd = PhotoTestClock.date(2024, 12, 31)
        flow.destinationURL = URL(fileURLWithPath: "/tmp/dest")

        let plan = flow.makePlan()

        #expect(plan?.photoOptions.dateRangeStart == nil)
        #expect(plan?.photoOptions.dateRangeEnd == nil)
    }

    @Test func photosAndVideosOnlyTogetherBlockContinuation() {
        let flow = SetupFlow()
        flow.includePhotos = true
        flow.photosOnly = true
        flow.videosOnly = true
        #expect(!flow.canContinue)
        flow.videosOnly = false
        #expect(flow.canContinue)
    }
}
