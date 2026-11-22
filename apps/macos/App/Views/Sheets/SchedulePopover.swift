import NoNeedCloudCore
import SwiftUI

/// Schedule settings. They're saved now; the scheduler that acts on them is M6.
struct SchedulePopover: View {
    let model: AppModel

    var body: some View {
        Form {
            Picker("Back up", selection: model.planBinding(\.schedule.frequency)) {
                Text("Manually").tag(ScheduleSettings.Frequency.off)
                Text("Every hour").tag(ScheduleSettings.Frequency.hourly)
                Text("Every day").tag(ScheduleSettings.Frequency.daily)
                Text("Every week").tag(ScheduleSettings.Frequency.weekly)
                Text("Every month").tag(ScheduleSettings.Frequency.monthly)
            }

            switch model.plan.schedule.frequency {
            case .weekly:
                Picker("On", selection: model.planBinding(\.schedule.weekday)) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                timePicker
            case .monthly:
                Picker("On day", selection: model.planBinding(\.schedule.dayOfMonth)) {
                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                }
                timePicker
            case .daily:
                timePicker
            case .off, .hourly:
                EmptyView()
            }

            Toggle("Start NoNeedCloud at login", isOn: model.planBinding(\.schedule.startAtLogin))

            Text("Scheduled backups run once the scheduler ships. For now, start backups manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var timePicker: some View {
        DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = model.plan.schedule.timeOfDayMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.updatePlan { $0.schedule.timeOfDayMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
            }
        )
    }
}
