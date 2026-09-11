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
    // Which limits appear as text in the menu bar, by metric key ("session",
    // "weekly_all", "weekly_scoped:Fable"). Stored order is ignored — the menu
    // bar always draws them in the same order the popover does.
    @Published var menuBarMetrics: [String] { didSet { defaults.set(menuBarMetrics, forKey: "menuBarMetrics") } }
    // Which limits get a ring, by metric key. Order here is ignored — rings are
    // drawn outermost-first in the same order the popover lists them, so the
    // outer ring keeps meaning what it has always meant. Capped at three: a
    // fourth has too little circumference left to read as an arc.
    @Published var menuBarRings: [String] { didSet { defaults.set(menuBarRings, forKey: "menuBarRings") } }

    // How much name each of those percentages carries — full, one letter, or none.
    @Published var menuBarLabelStyle: MenuBarLabelStyle {
        didSet { defaults.set(menuBarLabelStyle.rawValue, forKey: "menuBarLabelStyle") }
    }
    // true  -> "Resets at 1:00 PM"  (plan against the clock)
    // false -> "Resets in 3h"       (plan against a duration)
    @Published var showEndTimes: Bool { didSet { defaults.set(showEndTimes, forKey: "showEndTimes") } }

    // Local LLM monitoring (Ollama / LM Studio)
    @Published var watchLocalLLMs: Bool  { didSet { defaults.set(watchLocalLLMs, forKey: "watchLocalLLMs") } }
    @Published var notifyLocalDone: Bool { didSet { defaults.set(notifyLocalDone, forKey: "notifyLocalDone") } }
    // Prompt text is the one genuinely sensitive thing we surface, so it gets its
    // own switch — you can keep the busy indicator without showing what you asked.
    @Published var showLocalTitles: Bool { didSet { defaults.set(showLocalTitles, forKey: "showLocalTitles") } }

    private init() {
        // First-run defaults.
        defaults.register(defaults: [
            "refreshMinutes": 3,
            "notifyAt80": true,
            "notifyAt100": true,
            "notifyForecast": true,
            "showMenuBarText": true,
            "menuBarMetrics": ["session"],
            "menuBarRings": ["session", "weekly_all"],   // exactly today's icon
            "menuBarLabelStyle": MenuBarLabelStyle.full.rawValue,
            "showEndTimes": true,
            "watchLocalLLMs": true,
            "notifyLocalDone": true,
            "showLocalTitles": true,
        ])
        // didSet does not fire during init, so these don't re-write the defaults.
        menuBarRings    = defaults.stringArray(forKey: "menuBarRings") ?? ["session", "weekly_all"]
        refreshMinutes  = defaults.integer(forKey: "refreshMinutes")
        notifyAt80      = defaults.bool(forKey: "notifyAt80")
        notifyAt100     = defaults.bool(forKey: "notifyAt100")
        notifyForecast  = defaults.bool(forKey: "notifyForecast")
        showMenuBarText = defaults.bool(forKey: "showMenuBarText")
        menuBarMetrics  = defaults.stringArray(forKey: "menuBarMetrics") ?? ["session"]
        menuBarLabelStyle = MenuBarLabelStyle(rawValue: defaults.string(forKey: "menuBarLabelStyle") ?? "") ?? .full
        showEndTimes    = defaults.bool(forKey: "showEndTimes")
        watchLocalLLMs  = defaults.bool(forKey: "watchLocalLLMs")
        notifyLocalDone = defaults.bool(forKey: "notifyLocalDone")
        showLocalTitles = defaults.bool(forKey: "showLocalTitles")
    }

    var refreshInterval: TimeInterval { TimeInterval(max(1, refreshMinutes) * 60) }
}
