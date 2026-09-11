import SwiftUI

// The Preferences window contents. Bound directly to Preferences.shared, so any
// change is saved and picked up live by the rest of the app.
struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var launchAtLogin = LoginItem.isEnabled

    // 13:00 today, purely to show the user's own time format in the picker.
    private var sampleTime: Date {
        Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // Ticking one of the menu bar rings on or off. Three is the ceiling: a
    // fourth ring has too little circumference left to read as an arc rather
    // than a dot.
    private func ringed(_ key: String) -> Binding<Bool> {
        Binding(get: { prefs.menuBarRings.contains(key) },
                set: { on in
                    var keys = prefs.menuBarRings.filter { $0 != key }
                    if on { keys.append(key) }
                    prefs.menuBarRings = keys
                })
    }

    private var ringLimitReached: Bool { prefs.menuBarRings.count >= 3 }

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
            AccountsSection()

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
                // The rings are the primary indicator, so they come first.
                // Outermost is whichever of these the popover lists first, so
                // the outer ring keeps meaning what it always has.
                Text("Rings — outermost first")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(viewModel.menuBarChoices) { metric in
                    Toggle(metric.label, isOn: ringed(metric.key))
                        .disabled(ringLimitReached && !prefs.menuBarRings.contains(metric.key))
                        .padding(.leading, 18)
                }
                if ringLimitReached {
                    Text("Three is the most that stays readable at menu bar size.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

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
                    Text("End time — \(DateUtils.clockTime(sampleTime))").tag(true)
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
        .frame(width: 400, height: 620)
    }
}
