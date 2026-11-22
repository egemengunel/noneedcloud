import Foundation

final class PhotoBackupCoordinator: @unchecked Sendable {
    let state: CopyEngineState

    private let source: any PhotoLibrarySource
    private let destinationRoot: URL
    private let options: PhotoOptions
    private let stateURL: URL
    private let cancelFlag = CancellationFlag()
    private let calendar: Calendar
    private let today: Date

    init(
        source: any PhotoLibrarySource,
        destinationURL: URL,
        options: PhotoOptions,
        stateURL: URL,
        calendar: Calendar = .current,
        today: Date = Date()
    ) {
        self.state = CopyEngineState()
        self.source = source
        self.destinationRoot = destinationURL.appendingPathComponent("Photos", isDirectory: true)
        self.options = options
        self.stateURL = stateURL
        self.calendar = calendar
        self.today = today
    }

    nonisolated func stop() {
        cancelFlag.cancel()
    }

    private struct PlannedAsset {
        var asset: PhotoAsset
        var components: [PhotoComponent]
    }

    func run() async -> CopyRunResult {
        let startedAt = Date()
        let index = PhotoIncrementalIndex(url: stateURL)
        var copied = 0
        var skipped = 0
        var failed = 0
        var bytesCopied: Int64 = 0
        var bytesSkipped: Int64 = 0
        var lastPublish = Date.distantPast

        func publishIfDue(currentFile: String, force: Bool = false) async {
            let now = Date()
            guard force || now.timeIntervalSince(lastPublish) >= 0.1 else { return }
            lastPublish = now
            await state.report(
                currentFile: currentFile,
                itemsCopied: copied,
                itemsSkipped: skipped,
                bytesCopied: bytesCopied,
                bytesSkipped: bytesSkipped
            )
        }

        func finish(outcome: CopyRunResult.Outcome) async -> CopyRunResult {
            try? index.save()
            let cancelled = outcome == .cancelled
            await state.finish(cancelled: cancelled)
            return CopyRunResult(
                outcome: outcome,
                itemsCopied: copied,
                itemsSkipped: skipped,
                itemsFailed: failed,
                bytesCopied: bytesCopied,
                itemsProtected: index.count
            )
        }

        await state.begin(itemsTotal: 0, bytesTotal: 0, startedAt: startedAt)

        let enumerated: [PhotoAsset]
        do {
            enumerated = try await source.enumerateAssets(includingShared: options.includeSharedAlbums)
        } catch {
            await state.recordError(BackupFileError(path: destinationRoot.path, reason: error.localizedDescription))
            failed += 1
            return await finish(outcome: .failed)
        }

        var planned: [PlannedAsset] = []
        for asset in enumerated where PhotoAssetFilter.include(asset, options: options, calendar: calendar, today: today) {
            if cancelFlag.isCancelled { break }
            do {
                let components = PhotoAssetFilter.selectedComponents(
                    try await source.components(for: asset),
                    asset: asset,
                    options: options
                )
                if components.isEmpty {
                    throw PhotoSourceError.componentUnavailable(asset.filename)
                }
                planned.append(PlannedAsset(asset: asset, components: components))
            } catch {
                failed += 1
                await state.recordError(BackupFileError(path: asset.filename, reason: error.localizedDescription))
            }
        }

        let totalBytes = planned.reduce(Int64(0)) {
            $0 + $1.components.reduce(Int64(0)) { $0 + ($1.byteSize ?? 0) }
        }
        await state.begin(itemsTotal: planned.count, bytesTotal: totalBytes, startedAt: startedAt)

        var usedNames: [String: Set<String>] = [:]

        for plannedAsset in planned {
            if cancelFlag.isCancelled { break }
            let asset = plannedAsset.asset
            let components = plannedAsset.components
            let fingerprints = components.map(\.fingerprint)
            let folderPath = PhotoLayout.relativeDayPath(for: asset, today: today, calendar: calendar)
            let folder = destinationRoot.appendingPathComponent(folderPath, isDirectory: true)
            let assetModification = (asset.modificationDate ?? asset.creationDate ?? today).timeIntervalSince1970
            let known = index.entry(for: asset.localIdentifier)

            if let known,
               known.modificationDate == assetModification,
               known.fingerprints == fingerprints {
                skipped += 1
                bytesSkipped += components.reduce(Int64(0)) { $0 + ($1.byteSize ?? 0) }
                await publishIfDue(currentFile: asset.filename)
                continue
            }

            var assignedPaths: [String: String] = [:]
            var assetBytes: Int64 = 0
            var assetFailed = false
            for component in components {
                if cancelFlag.isCancelled { break }
                do {
                    let name = try reserveFileName(
                        component: component,
                        folder: folder,
                        folderPath: folderPath,
                        preferred: known?.paths[component.kind.rawValue],
                        usedNames: &usedNames
                    )
                    let destinationFile = folder.appendingPathComponent(name)
                    let bytes = try await source.export(component: component, of: asset, to: destinationFile)
                    try? FileManager.default.setAttributes(
                        [.modificationDate: PhotoLayout.backupDate(for: asset, today: today, calendar: calendar)],
                        ofItemAtPath: destinationFile.path
                    )
                    assignedPaths[component.kind.rawValue] = "\(folderPath)/\(name)"
                    assetBytes += bytes
                } catch {
                    assetFailed = true
                    failed += 1
                    await state.recordError(BackupFileError(path: "\(folderPath)/\(component.filename)", reason: error.localizedDescription))
                    break
                }
            }
            if assetFailed || cancelFlag.isCancelled {
                for relativePath in assignedPaths.values {
                    try? FileManager.default.removeItem(
                        at: destinationRoot.appendingPathComponent(relativePath)
                    )
                }
            }
            if cancelFlag.isCancelled { break }
            if !assetFailed {
                index.update(asset.localIdentifier, entry: PhotoIndexEntry(
                    modificationDate: assetModification,
                    fingerprints: fingerprints,
                    paths: assignedPaths
                ))
                copied += 1
                bytesCopied += assetBytes
                if copied % 50 == 0 {
                    try? index.save()
                }
            }
            await publishIfDue(currentFile: asset.filename, force: true)
        }

        return await finish(outcome: cancelFlag.isCancelled ? .cancelled : .completed)
    }

    private func reserveFileName(
        component: PhotoComponent,
        folder: URL,
        folderPath: String,
        preferred: String?,
        usedNames: inout [String: Set<String>]
    ) throws -> String {
        var used = usedNames[folderPath] ?? basenames(in: folder)
        defer { usedNames[folderPath] = used }
        if let preferred {
            let fileName = (preferred as NSString).lastPathComponent
            used.insert(fileName.lowercased())
            return fileName
        }
        let name = PhotoLayout.uniqueFileName(candidate: component.filename, usedNames: used)
        used.insert(name.lowercased())
        return name
    }

    private func basenames(in folder: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return Set(names.map { $0.lowercased() })
    }
}
