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
            "watchLocalLLMs": true,
            "notifyLocalDone": true,
            "showLocalTitles": true,
        ])
        // didSet does not fire during init, so these don't re-write the defaults.
        refreshMinutes  = defaults.integer(forKey: "refreshMinutes")
        notifyAt80      = defaults.bool(forKey: "notifyAt80")
        notifyAt100     = defaults.bool(forKey: "notifyAt100")
        notifyForecast  = defaults.bool(forKey: "notifyForecast")
        showMenuBarText = defaults.bool(forKey: "showMenuBarText")
        watchLocalLLMs  = defaults.bool(forKey: "watchLocalLLMs")
        notifyLocalDone = defaults.bool(forKey: "notifyLocalDone")
        showLocalTitles = defaults.bool(forKey: "showLocalTitles")
    }

    var refreshInterval: TimeInterval { TimeInterval(max(1, refreshMinutes) * 60) }
}
