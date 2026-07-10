import Foundation
import Combine

// User-adjustable settings, persisted in UserDefaults so they survive relaunches.
// A single shared instance is read by the view model, notification manager, and
// menu bar; the Settings window binds to it directly.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
    @Published var notifyAt80: Bool     { didSet { defaults.set(notifyAt80, forKey: "notifyAt80") } }
    @Published var notifyAt100: Bool    { didSet { defaults.set(notifyAt100, forKey: "notifyAt100") } }
    @Published var notifyForecast: Bool { didSet { defaults.set(notifyForecast, forKey: "notifyForecast") } }
    @Published var showMenuBarText: Bool { didSet { defaults.set(showMenuBarText, forKey: "showMenuBarText") } }

    private init() {
        // First-run defaults.
        defaults.register(defaults: [
            "refreshMinutes": 3,
            "notifyAt80": true,
            "notifyAt100": true,
            "notifyForecast": true,
            "showMenuBarText": true,
        ])
        // didSet does not fire during init, so these don't re-write the defaults.
        refreshMinutes  = defaults.integer(forKey: "refreshMinutes")
        notifyAt80      = defaults.bool(forKey: "notifyAt80")
        notifyAt100     = defaults.bool(forKey: "notifyAt100")
        notifyForecast  = defaults.bool(forKey: "notifyForecast")
        showMenuBarText = defaults.bool(forKey: "showMenuBarText")
    }

    var refreshInterval: TimeInterval { TimeInterval(max(1, refreshMinutes) * 60) }
}
