import SwiftUI
import UserNotifications


struct ReminderSettings {
    var enabled: Bool
    var hour: Int
    var minute: Int

    static var current: Self {
        let preferences = UserDefaults.standard
        return Self(enabled: preferences.object(forKey: "morningEnabled") as? Bool ?? false,
                    hour: preferences.object(forKey: "morningHour") as? Int ?? 8,
                    minute: preferences.object(forKey: "morningMinute") as? Int ?? 0)
    }
}

struct ReminderSettingsView: View {
    let refresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("morningEnabled") private var enabled = false
    @AppStorage("morningHour") private var hour = 8
    @AppStorage("morningMinute") private var minute = 0
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Tracker reminders").font(.title2.weight(.semibold))
            Text("Receive a quiet notification on days when a tracker reaches its date or a milestone.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Enable daily summary", isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    guard value else { status = ""; refresh(); return }
                    Task {
                        do {
                            let granted = try await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .badge])
                            status = granted ? "" : "Allow notifications for Tact in System Settings."
                            if granted { refresh() } else { enabled = false }
                        } catch {
                            status = error.localizedDescription
                            enabled = false
                        }
                    }
                }
            if enabled {
                DatePicker("Notification time", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
                }, set: {
                    hour = Calendar.current.component(.hour, from: $0)
                    minute = Calendar.current.component(.minute, from: $0)
                }), displayedComponents: .hourAndMinute)
                Text("Tact sends a summary only on days with a tracker event.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .onChange(of: hour) { _, _ in refresh() }
        .onChange(of: minute) { _, _ in refresh() }
    }
}

@MainActor
final class ProgressReminders {
    static let shared = ProgressReminders()
    private var revision = 0

    func refresh(_ trackers: [Tracker], settings: ReminderSettings) async throws {
        revision += 1
        let request = revision
        let calendar = Calendar.current
        let now = Date()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard request == revision else { throw CancellationError() }

        let wanted: [UNNotificationRequest] = settings.enabled
            ? summaryRequests(trackers, settings: settings, now: now, calendar: calendar) : []
        let wantedByID = Dictionary(uniqueKeysWithValues: wanted.map { ($0.identifier, $0) })
        let previous = pending.filter { $0.identifier.hasPrefix("tact.tracker-summary.") }
        center.removePendingNotificationRequests(withIdentifiers: previous.filter {
            wantedByID[$0.identifier] == nil
        }.map(\.identifier))
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.identifier, $0) })
        for notification in wanted {
            if let existing = previousByID[notification.identifier],
               existing.content.body == notification.content.body,
               (existing.trigger as? UNCalendarNotificationTrigger)?.dateComponents ==
                   (notification.trigger as? UNCalendarNotificationTrigger)?.dateComponents {
                continue
            }
            guard request == revision else { throw CancellationError() }
            try await center.add(notification)
        }
    }

    private func summaryRequests(_ trackers: [Tracker], settings: ReminderSettings,
                                 now: Date, calendar: Calendar) -> [UNNotificationRequest] {
        var groups: [Date: [String]] = [:]
        for tracker in trackers {
            for day in tracker.eventDates(from: now, count: 9, calendar: calendar) {
                if let time = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day),
                   time > now {
                    groups[time, default: []].append(tracker.name)
                }
            }
        }
        return groups.keys.sorted().prefix(48).map { time in
            let names = groups[time] ?? []
            let content = UNMutableNotificationContent()
            content.title = "Today in Tact"
            content.body = names.prefix(4).joined(separator: " · ") +
                (names.count > 4 ? " · +\(names.count - 4) more" : "")
            content.interruptionLevel = .passive
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "tact.tracker-summary.\(Int(calendar.startOfDay(for: time).timeIntervalSince1970))"
            return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        }
    }
}

