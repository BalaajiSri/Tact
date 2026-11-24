import SwiftUI

struct SettingsView: View {
    @ObservedObject var loginItem: LoginItem
    let refresh: () -> Void
    @AppStorage("tactAppearance") private var appearance = "System"
    @State private var showReminders = false

    var body: some View {
        TabView {
            Form {
                Toggle("Open at login", isOn: Binding(get: { loginItem.enabled }, set: loginItem.setEnabled))
                if loginItem.status == .requiresApproval {
                    Button("Approve in System Settings…", action: loginItem.openSettings)
                }
                if let error = loginItem.errorMessage { Text(error).foregroundStyle(.secondary) }
            }
            .padding()
            .tabItem { Label("General", systemImage: "gear") }

            Form { SoundSettings() }
                .padding()
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }

            Form {
                Text("Configure tracker reminders and send a test notification.")
                Button("Tracker Reminders…") { showReminders = true }
            }
            .padding()
            .tabItem { Label("Notifications", systemImage: "bell") }

            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
            }
            .padding()
            .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showReminders) { ReminderSettingsView(refresh: refresh) }
        .onAppear { loginItem.refresh() }
    }
}
