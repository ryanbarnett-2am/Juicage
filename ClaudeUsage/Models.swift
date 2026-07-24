import Foundation

// Lightweight debug logging. In release builds this compiles away to nothing,
// so no diagnostic noise ships to users.
func dlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[ClaudeUsage] \(message())")
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
}

// A snapshot of one workspace's whole usage picture.
struct WorkspaceUsage: Equatable, Identifiable {
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

    var id: String { workspaceID ?? workspaceName ?? "workspace" }

    init() {
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
    case unknown                            // not enough data yet
    // 🟢 on pace to finish under 100%. `spareBeforeReset` is how much longer your
    // allowance would last past the reset — your time margin (nil when idle).
    case safe(projectedPercent: Int, spareBeforeReset: TimeInterval?)
    case willHit(beforeReset: TimeInterval) // 🟠 on pace to hit 100% this early
    case atLimit                            // 🔴 already at/over 100%

    var isAlerting: Bool {
        switch self {
        case .willHit, .atLimit: return true
        case .unknown, .safe:    return false
        }
    }
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

    // Formats a plain duration (in seconds) as "3h 56m" / "42m".
    static func duration(_ seconds: TimeInterval) -> String {
        let secs = max(0, Int(seconds.rounded()))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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
