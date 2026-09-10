import Foundation

// Lightweight debug logging. In release builds this compiles away to nothing,
// so no diagnostic noise ships to users.
func dlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[ClaudeUsage] \(message())")
    fflush(stdout)   // flush so output reaches a redirected log file immediately
    #endif
}

// MARK: - Core data types

// One usage limit — e.g. the 5-hour session, the weekly "all models" cap,
// or a per-model weekly cap like Fable. Every limit has the same shape,
// so we model them all with one struct.
struct UsageMetric: Identifiable, Equatable {
    let key: String          // raw API key, e.g. "five_hour", "seven_day_fable"
    let label: String        // friendly name, e.g. "Fable"
    var percent: Int
    var resetAt: Date?
    var forecast: ForecastVerdict = .unknown

    var id: String { key }

    // Menu bar space is charged by the pixel, so the two fixed limits get
    // shortened. Per-model caps ("Fable") are already short enough to keep.
    var shortLabel: String {
        switch key {
        case "session":    return "Session"
        case "weekly_all": return "Week"
        default:           return label
        }
    }

    // One letter, for when even "Session" is too wide. C is for the current
    // session and W for the week; a per-model cap uses its own first letter.
    var initialLabel: String {
        switch key {
        case "session":    return "C"
        case "weekly_all": return "W"
        default:           return String(label.prefix(1)).uppercased()
        }
    }

    // How this limit reads in the menu bar under a given label style.
    func menuBarText(_ style: MenuBarLabelStyle) -> String {
        switch style {
        case .full:    return "\(shortLabel) \(percent)%"
        case .initial: return "\(initialLabel):\(percent)%"
        case .off:     return "\(percent)%"
        }
    }
}

// How much of a name each percentage carries in the menu bar. The whole reason
// this is adjustable is that a 14-inch screen runs out of menu bar long before
// a 27-inch one does (#12).
enum MenuBarLabelStyle: String, CaseIterable, Identifiable {
    case full       // "Session 31% · Week 35% · Fable 66%"
    case initial    // "C:31% W:35% F:66%"
    case off        // "31% · 35% · 66%"

    var id: String { rawValue }

    // Initials carry their own delimiter, so they don't need dots between them.
    var separator: String { self == .initial ? " " : " · " }

    // Shown in the Preferences picker — each option is its own example. Kept to
    // one example because the popup ellipsizes anything longer.
    var menuTitle: String {
        switch self {
        case .full:    return "Names — Session 31%"
        case .initial: return "Initials — C:31%"
        case .off:     return "Percent only — 31%"
        }
    }
}

// A snapshot of one workspace's whole usage picture.
struct WorkspaceUsage: Equatable, Identifiable {
    var providerID: String             // which service this came from, e.g. "claude"
    var providerName: String           // shown when more than one provider is enabled
    var workspaceID: String?           // org uuid — stable identity for the list & forecaster
    var workspaceName: String?
    var session: UsageMetric?          // the 5-hour "Current session"
    var weeklyAll: UsageMetric?        // the weekly "All models"
    var weeklyModels: [UsageMetric]    // per-model weekly caps (Fable, etc.)
    var extraEnabled: Bool
    var extraUsedCredits: Double?      // money spent, in major units (e.g. dollars)
    var extraMonthlyLimit: Double?     // your personal spend cap, when the API gives one
    var extraCurrency: String?         // e.g. "USD"
    var lastUpdated: Date?
    var error: String?

    // Prefixed with the provider: two services could easily both call something
    // "default", and this id drives both list identity and the forecaster's
    // per-metric history.
    var id: String { "\(providerID).\(workspaceID ?? workspaceName ?? "default")" }

    init() {
        providerID = "claude"
        providerName = "Claude"
        workspaceID = nil
        workspaceName = nil
        session = nil
        weeklyAll = nil
        weeklyModels = []
        extraEnabled = false
        extraUsedCredits = nil
        extraMonthlyLimit = nil
        extraCurrency = nil
        lastUpdated = nil
        error = nil
    }

    // Every limit in one flat list, in display order — handy for forecasting
    // and for the menu bar (which cares about the worst offender).
    var allMetrics: [UsageMetric] {
        var out: [UsageMetric] = []
        if let session { out.append(session) }
        if let weeklyAll { out.append(weeklyAll) }
        out.append(contentsOf: weeklyModels)
        return out
    }
}

// MARK: - Forecast result

// The result of projecting your current burn rate forward to a limit's reset.
enum ForecastVerdict: Equatable {
    case unknown                            // nothing to say yet (no usage / can't compute)
    case warmingUp                          // pace looks steep, but too little used to trust — "calculating"
    // 🟢 on pace to finish under 100%. `spareBeforeReset` is how much longer your
    // allowance would last past the reset — your time margin (nil when idle).
    // `runsOutIn` is how long the allowance itself lasts from now at this pace.
    case safe(projectedPercent: Int, spareBeforeReset: TimeInterval?, runsOutIn: TimeInterval)
    // 🟠 on pace to hit 100% before the window resets. `runsOutIn` is the number
    // that actually matters to a person: how long you have left.
    case willHit(beforeReset: TimeInterval, runsOutIn: TimeInterval)
    case atLimit                            // 🔴 already at/over 100%

    var isAlerting: Bool {
        switch self {
        case .willHit, .atLimit:            return true
        case .unknown, .warmingUp, .safe:   return false
        }
    }
}

// MARK: - Severity (the color tier)

// Three tiers so the color eases fine → getting-close → over, instead of jumping
// straight from blue to red. Drives both the menu bar rings and the popover bars.
enum Severity: Int, Comparable {
    case ok = 0     // comfortably on pace  → blue/neutral
    case warn = 1   // getting close        → orange
    case danger = 2 // over pace / very high → red
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

// Combines how much is used with the forecast. The "warn" middle catches both a
// high raw percentage and a forecast that's on pace but cutting it close.
func severity(percent: Int?, forecast: ForecastVerdict) -> Severity {
    if forecast.isAlerting { return .danger }              // will hit / at limit
    let p = percent ?? 0
    if p >= 80 { return .danger }
    if case .safe(let projected, _, _) = forecast, projected >= 85 { return .warn }
    if p >= 60 { return .warn }
    return .ok
}

// MARK: - Date & label helpers

enum DateUtils {
    // claude.ai timestamps look like "2026-05-20T22:50:00.101482+00:00".
    // We try the fractional-seconds parser first, then a plain one.
    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return isoFraction.date(from: text) ?? isoPlain.date(from: text)
    }

    // Compact countdown for the menu bar: "3h56m" or "42m".
    static func shortCountdown(to date: Date, now: Date = Date()) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    // Longer countdown for the popover: "3h 56m".
    static func mediumCountdown(to date: Date, now: Date = Date()) -> String {
        duration(date.timeIntervalSince(now))
    }

    // Short elapsed time for a running job: "8s" / "1m 12s" / "3h 4m".
    // Seconds matter here — local generations are often over in well under a
    // minute, and "0m" would read as nothing happening.
    static func compactElapsed(_ seconds: TimeInterval) -> String {
        let secs = max(0, Int(seconds.rounded()))
        if secs < 60 { return "\(secs)s" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(secs % 60)s"
    }

    // Formats a plain duration (in seconds) as "3h 56m" / "42m".
    static func duration(_ seconds: TimeInterval) -> String {
        let secs = max(0, Int(seconds.rounded()))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    // Menu-bar-sized clock: "1:00p" — about as wide as "3h56m".
    static func shortClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        return f.string(from: date).replacingOccurrences(of: "AM", with: "a")
                                   .replacingOccurrences(of: "PM", with: "p")
    }

    // Wall-clock time for something happening soon: "11:05 AM", or
    // "tomorrow 2:15 AM" when it crosses midnight.
    //
    // People plan against the clock, not against a duration — "do I get the
    // whole morning, or only until 11?" is answerable at a glance, while
    // "4h 30m" makes you do the arithmetic first.
    static func clockTime(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let time = f.string(from: date)
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           cal.isDate(date, inSameDayAs: tomorrow) { return "tomorrow \(time)" }
        return resetDate(date, now: now)
    }

    // Friendly absolute reset time for weekly caps: "Wed 11:00 AM".
    static func resetDate(_ date: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            f.dateFormat = "EEE h:mm a"
        } else {
            f.dateFormat = "MMM d, h:mm a"
        }
        return f.string(from: date)
    }

    // Turns a raw API key into a friendly label:
    //   "five_hour"          -> "Current Session"
    //   "seven_day"          -> "All Models"
    //   "seven_day_fable"    -> "Fable"
    //   "seven_day_claude_design" -> "Claude Design"
    static func label(forKey key: String) -> String {
        switch key {
        case "five_hour": return "Current Session"
        case "seven_day": return "All Models"
        default:
            // Strip a leading "seven_day_" / "five_hour_" and title-case the rest.
            var name = key
            for prefix in ["seven_day_", "five_hour_", "seven_day", "five_hour"] {
                if name.hasPrefix(prefix) {
                    name = String(name.dropFirst(prefix.count))
                    break
                }
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_ "))
            if name.isEmpty { return key }
            return name
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}
