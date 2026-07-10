import Foundation

// Turns claude.ai's usage JSON into a WorkspaceUsage. Kept separate from the
// web view so it's a pure function of its input — easy to reason about and to
// self-test (see runSelfTest below). This is the piece most likely to break if
// claude.ai changes its API shape, so it's isolated on purpose.
enum UsageParser {

    static func parseUsage(_ usageDict: [String: Any]) -> WorkspaceUsage {
        var result = WorkspaceUsage()

        // The "limits" array is claude.ai's canonical usage structure. Each entry
        // has a `kind` (session / weekly_all / weekly_scoped), a `percent`, a
        // `resets_at`, and — for per-model caps — a `scope` naming the model.
        // Reading this array is what makes Fable and other models appear.
        if let limits = usageDict["limits"] as? [[String: Any]] {
            for limit in limits {
                guard let pct = doubleValue(limit["percent"]) else { continue }
                let percent = Int(pct.rounded())
                let resetAt = DateUtils.parseISO(limit["resets_at"] as? String)
                let kind = limit["kind"] as? String ?? ""

                switch kind {
                case "session":
                    result.session = UsageMetric(key: "session", label: "Current Session",
                                                 percent: percent, resetAt: resetAt)
                case "weekly_all":
                    result.weeklyAll = UsageMetric(key: "weekly_all", label: "All Models",
                                                   percent: percent, resetAt: resetAt)
                case "weekly_scoped":
                    let name = scopedLabel(limit)
                    result.weeklyModels.append(
                        UsageMetric(key: "weekly_scoped:\(name)", label: name,
                                    percent: percent, resetAt: resetAt))
                default:
                    break
                }
            }
        }

        // Fallback for older API shape: if the limits array was missing, read the
        // top-level five_hour / seven_day objects instead.
        if result.session == nil, let obj = usageDict["five_hour"] as? [String: Any],
           let util = doubleValue(obj["utilization"]) {
            result.session = UsageMetric(key: "session", label: "Current Session",
                                         percent: Int(util.rounded()),
                                         resetAt: DateUtils.parseISO(obj["resets_at"] as? String))
        }
        if result.weeklyAll == nil, let obj = usageDict["seven_day"] as? [String: Any],
           let util = doubleValue(obj["utilization"]) {
            result.weeklyAll = UsageMetric(key: "weekly_all", label: "All Models",
                                           percent: Int(util.rounded()),
                                           resetAt: DateUtils.parseISO(obj["resets_at"] as? String))
        }

        // Extra pay-as-you-go usage lives under "spend" now (older API used
        // "extra_usage"). Only shown when the user has enabled it.
        if let spend = usageDict["spend"] as? [String: Any], (spend["enabled"] as? Bool) == true {
            result.extraEnabled = true
            if let used = spend["used"] as? [String: Any], let minor = doubleValue(used["amount_minor"]) {
                let exponent = doubleValue(used["exponent"]) ?? 2
                result.extraUsedCredits = minor / pow(10, exponent)
            }
            result.extraMonthlyLimit = doubleValue(spend["cap"])
        }

        // Show the per-model bars in a stable order (highest usage first).
        result.weeklyModels.sort { $0.percent > $1.percent }
        return result
    }

    // Pulls a friendly model name out of a weekly_scoped limit's `scope` object,
    // e.g. scope.model.display_name -> "Fable".
    static func scopedLabel(_ limit: [String: Any]) -> String {
        if let scope = limit["scope"] as? [String: Any] {
            if let model = scope["model"] as? [String: Any],
               let name = model["display_name"] as? String, !name.isEmpty {
                return name
            }
            if let surface = scope["surface"] as? String, !surface.isEmpty {
                return surface.capitalized
            }
        }
        return "Weekly (scoped)"
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    // MARK: - Self-test

    // Parses a sample of the real API shape and checks the numbers land where we
    // expect. Runs once at launch in debug builds; if claude.ai changes its API,
    // this logs a loud FAILED line so you know the parser needs updating — before
    // you're staring at a blank popover wondering what broke.
    #if DEBUG
    static func runSelfTest() {
        let sample = """
        {"limits":[
          {"kind":"session","percent":15,"resets_at":"2026-07-09T22:50:00.064762+00:00"},
          {"kind":"weekly_all","percent":3,"resets_at":"2026-07-15T16:00:00.064787+00:00"},
          {"kind":"weekly_scoped","percent":2,"resets_at":"2026-07-15T16:00:00.065150+00:00","scope":{"model":{"display_name":"Fable"}}}
        ]}
        """
        guard let data = sample.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            dlog("parser self-test FAILED ✗ — sample JSON did not parse")
            return
        }

        let ws = parseUsage(dict)
        var problems: [String] = []
        if ws.session?.percent != 15 {
            problems.append("session expected 15, got \(String(describing: ws.session?.percent))")
        }
        if ws.weeklyAll?.percent != 3 {
            problems.append("weeklyAll expected 3, got \(String(describing: ws.weeklyAll?.percent))")
        }
        if ws.weeklyModels.first(where: { $0.label == "Fable" })?.percent != 2 {
            problems.append("Fable per-model bar missing or wrong")
        }

        if problems.isEmpty {
            dlog("parser self-test PASSED ✓")
        } else {
            dlog("parser self-test FAILED ✗ — \(problems.joined(separator: "; ")) "
                 + "— claude.ai's API shape may have changed; update UsageParser.parseUsage.")
        }
    }
    #endif
}
