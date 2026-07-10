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

            Section("Menu Bar") {
                Toggle("Show percentage next to the ring", isOn: $prefs.showMenuBarText)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
    }
}
