import SwiftUI

struct PlanEditorTarget: Identifiable {
    let id = UUID()
    let plan: BackupPlan?
}

final class ScheduleForm: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case manual, hourly, daily, weekly, monthly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .manual: "Manual"
            case .hourly: "Hourly"
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            }
        }
    }

    @Published var kind: Kind
    @Published var hour: Int
    @Published var minute: Int
    @Published var weekday: Int
    @Published var day: Int

    init(schedule: Schedule) {
        switch schedule {
        case .manual:
            kind = .manual
            hour = 9
            minute = 0
            weekday = 2
            day = 1
        case .hourly:
            kind = .hourly
            hour = 9
            minute = 0
            weekday = 2
            day = 1
        case .daily(let hour, let minute):
            kind = .daily
            self.hour = hour
            self.minute = minute
            weekday = 2
            day = 1
        case .weekly(let weekday, let hour, let minute):
            kind = .weekly
            self.weekday = weekday
            self.hour = hour
            self.minute = minute
            day = 1
        case .monthly(let day, let hour, let minute):
            kind = .monthly
            self.day = day
            self.hour = hour
            self.minute = minute
            weekday = 2
        }
    }

    var schedule: Schedule {
        switch kind {
        case .manual: .manual
        case .hourly: .hourly
        case .daily: .daily(hour: hour, minute: minute)
        case .weekly: .weekly(weekday: weekday, hour: hour, minute: minute)
        case .monthly: .monthly(day: day, hour: hour, minute: minute)
        }
    }
}

/// Create or edit a backup plan. Reuses the wizard's source and destination
/// editors (they are plain views over a SetupFlow); adds naming and the
/// schedule picker.
struct PlanEditorView: View {
    static let defaultNewName = "My Backup Plan"

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @StateObject private var flow: SetupFlow
    @StateObject private var scheduleForm: ScheduleForm
    @State private var planId: UUID?
    @State private var name: String

    init(model: AppModel, plan: BackupPlan?) {
        self.model = model
        let flow = SetupFlow()
        if let plan {
            flow.sourceFolderURLs = plan.sourceFolderURLs
            for source in plan.sources {
                switch source {
                case .folder: break
                case .icloudDrive: flow.includeICloudDrive = true
                case .appContainer(let groupID, _):
                    if groupID == "com~apple~Pages" { flow.includePages = true }
                    if groupID == "com~apple~Numbers" { flow.includeNumbers = true }
                }
            }
            flow.includePhotos = plan.includePhotos
            flow.photosOnly = plan.photoOptions.photosOnly
            flow.videosOnly = plan.photoOptions.videosOnly
            flow.includeEdits = plan.photoOptions.includeEdits
            flow.includeSharedAlbums = plan.photoOptions.includeSharedAlbums
            flow.mirrorEnabled = plan.mirrorOptions.enabled
            flow.mirrorRetention = plan.mirrorOptions.retention
            if let start = plan.photoOptions.dateRangeStart {
                flow.usePhotoDateRange = true
                flow.photoDateRangeStart = start
            }
            if let end = plan.photoOptions.dateRangeEnd {
                flow.usePhotoDateRange = true
                flow.photoDateRangeEnd = end
            }
            flow.keychain = model.keychain
            flow.existingDestination = plan.destination
            switch plan.destination {
            case .folder(let url):
                flow.destinationURL = url
            case .s3(let config):
                flow.destinationProvider = .s3
                flow.s3Endpoint = config.endpointURL?.absoluteString ?? ""
                flow.s3Region = config.region
                flow.s3Bucket = config.bucket
                flow.s3Prefix = config.prefix
                flow.s3AccessKeyID = config.accessKeyID
                flow.s3UsePathStyle = config.usePathStyle
            case .onedrive:
                flow.destinationProvider = .onedrive
            case .gdrive:
                flow.destinationProvider = .gdrive
            }
        }
        _flow = StateObject(wrappedValue: flow)
        _scheduleForm = StateObject(wrappedValue: ScheduleForm(schedule: plan?.schedule ?? .manual))
        _planId = State(initialValue: plan?.id)
        _name = State(initialValue: plan?.name ?? Self.defaultNewName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Plan Name", text: $name)
                    SourcesStep(flow: flow)
                    DestinationStep(flow: flow)
                    mirroringSection
                    scheduleSection
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(planId == nil ? "Create Plan" : "Save Changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.makePlan(name: name) == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var mirroringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mirroring")
                .font(.headline)
            Toggle("Move Deleted Items to a Deleted Folder", isOn: $flow.mirrorEnabled)
            if flow.mirrorEnabled {
                Picker("Keep Deleted Items", selection: $flow.mirrorRetention) {
                    Text("Forever").tag(Retention.forever)
                    Text("90 Days").tag(Retention.days(90))
                    Text("30 Days").tag(Retention.days(30))
                    Text("Until Next Backup").tag(Retention.untilNextBackup)
                }
                Text("When a source item is deleted, its backup copy is moved to Deleted/<date>/ on the next run and purged per this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if flow.destinationProvider != .folder {
                    Text("This destination type does not support mirroring yet — deletions will not be mirrored until a folder destination is selected.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.headline)
            Picker("Runs", selection: $scheduleForm.kind) {
                ForEach(ScheduleForm.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch scheduleForm.kind {
            case .manual:
                Text("You start this plan yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .hourly:
                Text("Runs at the top of every hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .daily, .weekly, .monthly:
                HStack(spacing: 12) {
                    Picker("Hour", selection: $scheduleForm.hour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    Picker("Minute", selection: $scheduleForm.minute) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }

            if scheduleForm.kind == .weekly {
                Picker("Weekday", selection: $scheduleForm.weekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
            }

            if scheduleForm.kind == .monthly {
                Picker("Day of Month", selection: $scheduleForm.day) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Text("Months without this day use their last day instead (day 31 becomes Feb 28).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(scheduleForm.schedule.summary)
                .font(.callout)
        }
        .padding(20)
    }

    private func save() {
        guard var plan = flow.makePlan(name: name) else { return }
        plan.schedule = scheduleForm.schedule
        if let planId {
            plan.id = planId
            model.updatePlan(plan)
        } else {
            model.addPlan(plan)
        }
        dismiss()
    }
}
