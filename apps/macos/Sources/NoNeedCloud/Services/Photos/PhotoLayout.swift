import Foundation

enum PhotoLayout {
    static func backupDate(for asset: PhotoAsset, today: Date, calendar: Calendar = .current) -> Date {
        asset.creationDate ?? asset.modificationDate ?? today
    }

    static func relativeDayPath(for asset: PhotoAsset, today: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: backupDate(for: asset, today: today, calendar: calendar)
        )
        return String(
            format: "%04d/%02d/%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func uniqueFileName(candidate: String, usedNames: Set<String>) -> String {
        guard usedNames.contains(candidate.lowercased()) else { return candidate }
        let stem = (candidate as NSString).deletingPathExtension
        let pathExtension = (candidate as NSString).pathExtension
        var index = 1
        while true {
            let proposal = pathExtension.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(pathExtension)"
            if !usedNames.contains(proposal.lowercased()) { return proposal }
            index += 1
        }
    }
}

enum PhotoAssetFilter {
    static func include(
        _ asset: PhotoAsset,
        options: PhotoOptions,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> Bool {
        if options.photosOnly, !asset.isPhoto { return false }
        if options.videosOnly, !asset.isVideo { return false }
        let date = PhotoLayout.backupDate(for: asset, today: today, calendar: calendar)
        if let start = options.dateRangeStart, date < calendar.startOfDay(for: start) { return false }
        if let end = options.dateRangeEnd {
            let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end)) ?? end
            if date > endOfDay { return false }
        }
        return true
    }

    static func select(
        _ assets: [PhotoAsset],
        options: PhotoOptions,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> [PhotoAsset] {
        assets.filter { include($0, options: options, calendar: calendar, today: today) }
    }

    static func selectedComponents(_ components: [PhotoComponent], asset: PhotoAsset, options: PhotoOptions) -> [PhotoComponent] {
        var kinds: Set<PhotoComponentKind> = [.original]
        if options.includeEdits {
            if asset.hasEdits { kinds.insert(.edited) }
            if asset.isLivePhoto { kinds.insert(.livePhotoMovie) }
            if asset.isRawPair { kinds.insert(.rawSidecar) }
        }
        return components
            .filter { kinds.contains($0.kind) }
            .sorted { $0.filename == $1.filename ? $0.kind.rawValue < $1.kind.rawValue : $0.filename < $1.filename }
    }
}
