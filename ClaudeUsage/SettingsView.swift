import SwiftUI

// The Preferences window contents. Bound directly to Preferences.shared, so any
// change is saved and picked up live by the rest of the app.
struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var launchAtLogin = LoginItem.isEnabled

    // Ticking one of the menu bar limits on or off. Stored as a list of metric
    // keys rather than a fixed set of switches, so a cap we've never heard of
    // still gets a working checkbox the day the account grows one.
    private func shown(_ key: String) -> Binding<Bool> {
        Binding(get: { prefs.menuBarMetrics.contains(key) },
                set: { on in
                    var keys = prefs.menuBarMetrics.filter { $0 != key }
                    if on { keys.append(key) }
                    prefs.menuBarMetrics = keys
                })
    }

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
                Toggle("Show percentages next to the ring", isOn: $prefs.showMenuBarText)
                // Which limits those percentages are. The list is whatever your
                // account actually reports, so per-model caps show up on their own.
                ForEach(viewModel.menuBarChoices) { metric in
                    Toggle(metric.label, isOn: shown(metric.key))
                        .disabled(!prefs.showMenuBarText)
                        .padding(.leading, 18)
                }
                if viewModel.menuBarChoices.isEmpty {
                    Text("Your limits appear here once usage has loaded.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                // Three named limits is a wide menu bar, and a 14-inch screen
                // hasn't got it to spare — so the names can shrink to initials
                // or disappear entirely.
                Picker("Show limits as", selection: $prefs.menuBarLabelStyle) {
                    ForEach(MenuBarLabelStyle.allCases) { style in
                        Text(style.menuTitle).tag(style)
                    }
                }
                .disabled(!prefs.showMenuBarText)
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
