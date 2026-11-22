import NoNeedCloudCore
import SwiftUI

/// Backup History window, Figma "NoNeedCloud · Yedekleme geçmişi":
/// runs grouped by day on the left, the selected run's result, summary
/// and missed files on the right.
struct HistoryView: View {
    let model: AppModel
    @State private var filter: RunHistory.Filter = .all
    @State private var search = ""
    @State private var selectedID: BackupRun.ID?

    private var days: [RunHistory.Day] {
        RunHistory.days(from: model.planRuns, filter: filter, search: search)
    }

    private var visibleRuns: [BackupRun] { days.flatMap(\.runs) }

    private var selectedRun: BackupRun? {
        visibleRuns.first { $0.id == selectedID } ?? visibleRuns.first
    }

    var body: some View {
        Group {
            if model.planRuns.isEmpty {
                ContentUnavailableView(
                    "No backups yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Runs appear here after your first backup.")
                )
            } else {
                HStack(spacing: 0) {
                    RunList(days: days, filter: $filter, selectedID: selectedRun?.id) { selectedID = $0 }
                        .frame(width: 330)
                        .padding(12)
                    Rectangle().fill(Theme.lightLine).frame(width: 1)
                    Group {
                        if let run = selectedRun {
                            RunDetail(model: model, run: run)
                        } else {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Theme.window)
        .toolbar { AppTitleToolbarItem(title: String(localized: "Backup History")) }
        .toolbar(removing: .title)
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search history"))
        .navigationTitle(Text("Backup History"))
    }
}

// MARK: - Run list

private struct RunList: View {
    let days: [RunHistory.Day]
    @Binding var filter: RunHistory.Filter
    let selectedID: BackupRun.ID?
    let select: (BackupRun.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Runs")
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.42)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 15)
                .padding(.top, 15)

            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(RunHistory.Filter.allCases, id: \.self) { filter in
                        Text(HistoryText.filter(filter)).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 8) {
                    Text(HistoryText.filter(filter))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 9)
                .frame(width: 150, height: 34)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.top, 11)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                    ForEach(days) { day in
                        Text(HistoryText.day(day.date))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 3)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                        ForEach(day.runs) { run in
                            RunRow(run: run, isSelected: run.id == selectedID) { select(run.id) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 15)
            Text(HistoryText.runCount(days.reduce(0) { $0 + $1.runs.count }))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 15)
                .padding(.vertical, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lightLine))
    }
}

private struct RunRow: View {
    let run: BackupRun
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                OutcomeBadge(outcome: run.outcome, size: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(run.finishedAt.formatted(date: .omitted, time: .shortened))  ·  \(HistoryText.trigger(run.trigger))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(HistoryText.rowResult(run))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 61)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11).fill(Theme.blueTint)
                    RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.blueLine)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Rounded-square outcome icon (amber warning, green check, grey stop, red cross).
private struct OutcomeBadge: View {
    let outcome: BackupRun.Outcome
    var size: CGFloat = 40

    var body: some View {
        let style = OutcomeStyle(outcome)
        Image(systemName: style.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(style.iconColor)
            .frame(width: size, height: size)
            .background(style.tint, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct OutcomeStyle {
    let symbol: String
    let iconColor: Color
    let tint: Color
    let line: Color
    let textColor: Color

    init(_ outcome: BackupRun.Outcome) {
        switch outcome {
        case .succeeded:
            symbol = "checkmark.circle.fill"; iconColor = Theme.green; tint = Theme.mint; line = Theme.mintLine; textColor = Theme.green
        case .completedWithErrors:
            symbol = "exclamationmark.triangle"; iconColor = Theme.amber; tint = Theme.amberTint; line = Theme.amberLine; textColor = Theme.amber
        case .cancelled:
            symbol = "stop.fill"; iconColor = Theme.ink; tint = Theme.gray; line = Theme.line; textColor = Theme.muted
        case .failed:
            symbol = "xmark.octagon"; iconColor = Theme.red; tint = Theme.redTint; line = Theme.redLine; textColor = Theme.red
        }
    }
}

// MARK: - Run detail

private struct RunDetail: View {
    let model: AppModel
    let run: BackupRun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                SectionTitle("Run summary", size: 19)
                    .padding(.top, 19)
                    .padding(.bottom, 10)
                HStack(spacing: 12) {
                    MetricTile(value: Formatting.count(run.processedItems),
                               title: String(localized: "Total items"), caption: String(localized: "Items processed"))
                    MetricTile(value: Formatting.count(run.copiedItems),
                               title: String(localized: "New copies"), caption: String(localized: "In this run"))
                    MetricTile(value: Formatting.count(run.unchangedItems),
                               title: String(localized: "Unchanged"), caption: String(localized: "Already backed up"))
                    MetricTile(value: Formatting.count(run.failedItems),
                               title: String(localized: "Couldn't copy"), caption: String(localized: "Will be retried"))
                }
                missedSection
            }
            .padding(.horizontal, 19)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var banner: some View {
        let style = OutcomeStyle(run.outcome)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                StatusPill(text: HistoryText.outcome(run.outcome), color: style.textColor, background: style.tint)
                Text(HistoryText.title(run.finishedAt))
                    .font(.system(size: 33, weight: .bold))
                    .tracking(-0.78)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 9)
                Text("\(Formatting.sourcesSummary(model.plan))  →  \(Formatting.destinationName(model.plan))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 5)
                Text(HistoryText.timing(run))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            }
            Spacer()
            Image(systemName: style.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(style.iconColor)
                .frame(width: 51, height: 51)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(style.line))
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.tint, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style.line))
    }

    @ViewBuilder
    private var missedSection: some View {
        if !run.missedItems.isEmpty {
            SectionTitle("Files that couldn't be copied", size: 20)
                .padding(.top, 27)
                .padding(.bottom, 12)
            MissedFilesTable(items: run.missedItems)
            Label {
                Text("These items will be retried in the next backup.")
            } icon: {
                Image(systemName: "arrow.clockwise").foregroundStyle(Theme.blue)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.top, 15)
        } else {
            Label {
                Text(HistoryText.noMissedNote(run))
            } icon: {
                Image(systemName: run.outcome == .succeeded ? "checkmark.circle" : "info.circle")
                    .foregroundStyle(run.outcome == .succeeded ? Theme.green : Theme.muted)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.top, 22)
        }
    }
}

private struct MissedFilesTable: View {
    let items: [MissedItem]

    var body: some View {
        VStack(spacing: 0) {
            row(file: Text("File"), location: nil, reason: Text("Reason"), header: true)
                .frame(height: 38)
                .background(Theme.surface)
            Rectangle().fill(Theme.lightLine).frame(height: 1)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(file: Text(item.name), location: item.location, reason: Text(item.reason), header: false)
                    .frame(minHeight: 51)
                if index < items.count - 1 {
                    Rectangle().fill(Theme.lightLine).frame(height: 1).padding(.horizontal, 15)
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line))
    }

    private func row(file: Text, location: String?, reason: Text, header: Bool) -> some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    file
                        .font(.system(size: header ? 12 : 13, weight: .semibold))
                        .foregroundStyle(header ? Theme.muted : Theme.ink)
                    if let location {
                        Text(location)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                .frame(width: proxy.size.width * 0.555, alignment: .leading)
                reason
                    .font(.system(size: header ? 12 : 13, weight: header ? .semibold : .medium))
                    .foregroundStyle(header ? Theme.muted : Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Copy

private enum HistoryText {
    static func filter(_ filter: RunHistory.Filter) -> String {
        switch filter {
        case .all: String(localized: "All statuses")
        case .succeeded: String(localized: "Succeeded")
        case .withWarnings: String(localized: "With warnings")
        case .stopped: String(localized: "Stopped")
        case .failed: String(localized: "Failed")
        }
    }

    static func trigger(_ trigger: BackupRun.Trigger) -> String {
        switch trigger {
        case .manual: String(localized: "Manual backup")
        case .scheduled: String(localized: "Scheduled backup")
        }
    }

    static func outcome(_ outcome: BackupRun.Outcome) -> String {
        switch outcome {
        case .succeeded: String(localized: "Completed")
        case .completedWithErrors: String(localized: "Completed with warnings")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Stopped")
        }
    }

    static func rowResult(_ run: BackupRun) -> String {
        switch run.outcome {
        case .succeeded: return String(localized: "Succeeded")
        case .completedWithErrors:
            return run.failedItems == 1
                ? String(localized: "1 item couldn't be copied")
                : String(localized: "\(run.failedItems) items couldn't be copied")
        case .cancelled: return String(localized: "Stopped by you")
        case .failed: return run.failureReason ?? String(localized: "Failed")
        }
    }

    /// "Today, 22 November", "Yesterday, 21 November", "20 November".
    static func day(_ date: Date, now: Date = .now) -> String {
        let dayMonth = date.formatted(.dateTime.day().month(.wide))
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today, \(dayMonth)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(dayMonth)")
        }
        return dayMonth
    }

    /// "22 November 2026, 10:16".
    static func title(_ date: Date) -> String {
        "\(date.formatted(.dateTime.day().month(.wide).year())), \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "Started at 09:41  ·  took 35 min".
    static func timing(_ run: BackupRun) -> String {
        let start = run.startedAt.formatted(date: .omitted, time: .shortened)
        return String(localized: "Started at \(start)  ·  took \(Formatting.duration(run.duration))")
    }

    static func runCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 run") : String(localized: "\(count) runs")
    }

    static func noMissedNote(_ run: BackupRun) -> String {
        switch run.outcome {
        case .succeeded, .completedWithErrors: String(localized: "Every item was copied.")
        case .cancelled: String(localized: "Stopped before finishing. The next run picks up where this one left off.")
        case .failed: run.failureReason ?? String(localized: "The backup stopped unexpectedly.")
        }
    }
}
