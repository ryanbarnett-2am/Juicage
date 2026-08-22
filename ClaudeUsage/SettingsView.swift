import SwiftUI

// The Preferences window contents. Bound directly to Preferences.shared, so any
// change is saved and picked up live by the rest of the app.
struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Refresh") {
                Stepper("Check every \(prefs.refreshMinutes) min",
                        value: $prefs.refreshMinutes, in: 1...30)
            }

            Section("Notifications") {
                Toggle("When usage reaches 80%", isOn: $prefs.notifyAt80)
                Toggle("When a limit is reached (100%)", isOn: $prefs.notifyAt100)
                Toggle("When on pace to hit a limit", isOn: $prefs.notifyForecast)
            }

            Section("Display") {
                Toggle("Show percentage next to the ring", isOn: $prefs.showMenuBarText)
                Picker("Show times as", selection: $prefs.showEndTimes) {
                    Text("End time — 1:00 PM").tag(true)
                    Text("Time remaining — 3h 56m").tag(false)
                }
            }

            Section("Local Models") {
                Toggle("Watch Ollama and LM Studio", isOn: $prefs.watchLocalLLMs)
                Toggle("Notify when a local job finishes", isOn: $prefs.notifyLocalDone)
                    .disabled(!prefs.watchLocalLLMs)
                Toggle("Show what it's working on", isOn: $prefs.showLocalTitles)
                    .disabled(!prefs.watchLocalLLMs)
                Text("Prompt text is only available from LM Studio — Ollama never records it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 520)
    }
}
