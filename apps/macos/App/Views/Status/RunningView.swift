import NoNeedCloudCore
import SwiftUI

/// Figma "03 · Canlı yedekleme": navy progress card, stage list, live tiles.
struct RunningView: View {
    let model: AppModel
    let progress: BackupProgress

    private var destinationName: String {
        Formatting.destinationName(model.plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                ProgressCard(progress: progress, destinationName: destinationName)
                StagesCard(progress: progress, destinationName: destinationName)
                    .frame(width: 298)
            }
            .frame(height: 351)

            HStack(alignment: .top, spacing: 12) {
                MetricTile(
                    value: Formatting.count(progress.copiedItems),
                    title: String(localized: "New copies"),
                    caption: String(localized: "In this run")
                )
                MetricTile(
                    value: Formatting.bytes(progress.bytesWritten),
                    title: String(localized: "Data written"),
                    caption: destinationName
                )
                TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                    MetricTile(
                        value: Formatting.duration(context.date.timeIntervalSince(progress.startedAt)),
                        title: String(localized: "Elapsed"),
                        caption: String(localized: "Started at \(progress.startedAt.formatted(date: .omitted, time: .shortened))")
                    )
                }
                destinationCard
                    .frame(width: 298)
                    .padding(.leading, 6)
            }
            .padding(.top, 21)

            Spacer(minLength: 12)
            WindowFooter {
                Text("You can stop the backup without deleting existing copies.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } trailing: {
                Button("Stop") { model.stopBackup() }
                    .buttonStyle(.pillStop)
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
    }

    private var destinationCard: some View {
        HStack(alignment: .top, spacing: 13) {
            IconBadge(systemImage: Formatting.kindSymbol(model.plan.destinationDetails))
            VStack(alignment: .leading, spacing: 8) {
                Text(destinationName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(Formatting.kind(model.plan.destinationDetails).components(separatedBy: "  ·  ")[0])  ·  \(String(localized: "Connected"))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 1)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lightLine))
    }
}

private struct ProgressCard: View {
    let progress: BackupProgress
    let destinationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(Theme.lively).frame(width: 8, height: 8)
                Text(progress.phase == .enumerating ? "Scanning your sources" : "Backing up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.lightBlue)
            }
            Text(percentText)
                .font(.system(size: 90, weight: .bold))
                .tracking(-4.3)
                .foregroundStyle(.white)
                .monospacedDigit()
                // Digits roll as the percentage climbs.
                .contentTransition(.numericText(value: Double(percent)))
                .animation(.snappy(duration: 0.35), value: percent)
                .frame(height: 108)
                .padding(.top, 12)
            Text(remainingText)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 3)
                .padding(.leading, 4)

            ProgressBar(fraction: progress.fractionCompleted)
                .padding(.top, 20)
                .padding(.horizontal, 4)

            HStack {
                if let total = progress.totalItems {
                    Text("\(Formatting.count(progress.processedItems)) / \(Formatting.count(total)) items processed")
                    Spacer()
                    Text("\(Formatting.count(progress.remainingItems ?? 0)) items left")
                } else {
                    Text("Building the list of items…")
                    Spacer()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.lightBlue)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(progress.processedItems)))
            .animation(.snappy(duration: 0.3), value: progress.processedItems)
            .padding(.top, 16)
            .padding(.horizontal, 4)

            CurrentFile(item: progress.currentItem, destinationName: destinationName)
                .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }

    /// Whole percent, the value the numeric transition animates between.
    private var percent: Int {
        Int(((progress.fractionCompleted ?? 0) * 100).rounded(.down))
    }

    private var percentText: String {
        guard progress.fractionCompleted != nil else { return "–" }
        return (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private var remainingText: String {
        if let remaining = progress.estimatedRemaining { return Formatting.remaining(remaining) }
        return progress.phase == .enumerating ? String(localized: "Looking for new and changed items") : String(localized: "Estimating time left…")
    }
}

private struct ProgressBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.navyLine)
                if let fraction {
                    Capsule().fill(Theme.lively).frame(width: max(8, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.2), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Backup progress")
        .accessibilityValue(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
    }
}

private struct CurrentFile: View {
    let item: BackupProgress.CurrentItem?
    let destinationName: String

    private var fileName: String {
        item.map { ($0.displayPath as NSString).lastPathComponent } ?? " "
    }

    private var stageText: String {
        item.map { Formatting.stage($0.stage, kind: $0.kind, destination: destinationName) } ?? " "
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item?.kind == .file ? "doc" : "photo")
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 5) {
                // Each new file fades in as the previous one fades out.
                Text(fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                Text(stageText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.lightBlue)
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
            .animation(.easeInOut(duration: 0.18), value: fileName)
            .animation(.easeInOut(duration: 0.18), value: stageText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 63)
        .background(Theme.navy2, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.navyLine))
    }
}

/// Scan → Check → Download → Write (İşlem aşamaları).
private struct StagesCard: View {
    let progress: BackupProgress
    let destinationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Stages", size: 17)
            StepperList(items: items, spacing: 21, markerSize: 29)
                .padding(.top, 25)
                .animation(.easeInOut(duration: 0.25), value: currentIndex)
            Spacer(minLength: 8)
            Text("Check, download and write repeat for every item.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.lightLine))
    }

    /// 1 = scan, 2 = check, 3 = download, 4 = write.
    private var currentIndex: Int {
        if progress.phase == .enumerating { return 1 }
        switch progress.currentItem?.stage {
        case .check, nil: return 2
        case .fetch: return 3
        case .write, .release: return 4
        }
    }

    private var items: [StepperList.Item] {
        let rows: [(String, String)] = [
            (String(localized: "Scan"), progress.phase == .enumerating ? String(localized: "Scanning your sources") : String(localized: "Sources scanned")),
            (String(localized: "Check"), String(localized: "Compare with files at the destination")),
            (String(localized: "Download"), String(localized: "Fetch the original from iCloud")),
            (String(localized: "Write"), String(localized: "Copy the file to \(destinationName)")),
        ]
        return rows.enumerated().map { index, row in
            let id = index + 1
            let state: StepperList.Item.State = id < currentIndex ? .done : (id == currentIndex ? .current : .upcoming)
            return .init(id: id, title: row.0, subtitle: row.1, state: state)
        }
    }
}
