import Foundation

// Projects whether a limit will be hit before it resets.
//
// It uses your *average pace so far* within the window — current% projected out
// to the reset — rather than a recent burst rate. Average pace matches how these
// budgets behave: usage is bursty, and a big early prompt "comes back down" as
// the window elapses and as you idle. It's a trend signal, not a precise ETA.
//
// The warning is gated on *how much you've actually used*, not on elapsed time.
// A single early prompt (say 15%) extrapolates to a scary number but leaves you
// tons of headroom, so it's ignored. Torching 40% in the first ten minutes,
// though, is genuinely alarming no matter how early it is — and it warns then.
final class UsageForecaster {

    // Only raise the "you'll run out" alarm once you've consumed at least this
    // much of the limit. Below it, an over-pace projection is untrustworthy (a
    // sliver extrapolated) AND you still have plenty of runway, so stay quiet.
    // Above it, a fast burn is real and worth flagging immediately.
    private static let warnUsageFloor = 30.0   // percent

    // How long each kind of limit's window is. Keys may be workspace-prefixed
    // (e.g. "org123.session"), so match the suffix.
    static func windowLength(forKey key: String) -> TimeInterval {
        key.hasSuffix("session") ? 5 * 60 * 60 : 7 * 24 * 60 * 60
    }

    // Recent readings per limit, used for the burst rate below.
    private struct Sample { let at: Date; let percent: Double }
    private var history: [String: [Sample]] = [:]

    // How far back a "recent" rate looks, and the minimum span before we trust
    // one. Readings arrive every few minutes, so this is a handful of samples —
    // long enough to smooth a single blip, short enough to notice a burst.
    private static let recentWindow: TimeInterval = 20 * 60
    private static let minRecentSpan: TimeInterval = 5 * 60

    // Burn rate over the last few readings, in percent per second. Nil when
    // there isn't enough history yet to say.
    private func recentRate(key: String, now: Date, percent: Double) -> Double? {
        var samples = history[key] ?? []
        // A drop means the limit reset — old samples describe a different window.
        if let last = samples.last, percent < last.percent - 1 { samples = [] }
        samples.append(Sample(at: now, percent: percent))
        samples = samples.filter { now.timeIntervalSince($0.at) <= Self.recentWindow }
        history[key] = samples

        guard let first = samples.first, samples.count >= 2 else { return nil }
        let span = now.timeIntervalSince(first.at)
        guard span >= Self.minRecentSpan else { return nil }
        let delta = percent - first.percent
        guard delta > 0 else { return nil }      // idle or flat: nothing to warn about
        return delta / span
    }

    func update(key: String, percent: Int?, resetAt: Date?,
                now: Date = Date()) -> ForecastVerdict {
        guard let pctInt = percent, let resetAt else { return .unknown }
        let pct = Double(pctInt)
        if pct >= 100 { return .atLimit }

        let timeUntilReset = resetAt.timeIntervalSince(now)
        guard timeUntilReset > 0 else { return .unknown }

        let windowLength = Self.windowLength(forKey: key)
        let windowStart = resetAt.addingTimeInterval(-windowLength)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0, pct > 0 else { return .unknown }

        // Two rates, and we believe the worse of them.
        //
        // Average pace alone is too forgiving: idle all morning, then work hard,
        // and it still reports the gentle average right up until you're out —
        // "I think I'm fine and then five minutes later I'm out." Recent pace
        // alone is too jumpy, and was what fired a false alarm on the first
        // prompt of a session. Taking the max means a burst shortens the estimate
        // immediately, while the quiet average governs when nothing is happening.
        //
        // The *alarm* is still gated on the usage floor below, so a fast burst
        // early on shows a shrinking estimate without firing a notification.
        let avgRate = pct / elapsed                    // percent per second
        let burstRate = recentRate(key: key, now: now, percent: pct)
        let ratePerSec = max(avgRate, burstRate ?? 0)
        guard ratePerSec > 0 else { return .unknown }

        // Project forward from now at that rate. With the average rate this is
        // algebraically identical to pct / windowFraction, so nothing changes
        // when there's no burst.
        let projected = pct + ratePerSec * timeUntilReset
        let timeToLimit = (100.0 - pct) / ratePerSec   // from now, at this pace

        if projected >= 100 {
            // On pace to run out — but only sound the alarm once enough of the
            // budget is actually gone that it's real, not an early-prompt mirage.
            // Below the floor we're still "warming up": show it's calculating,
            // but don't alarm or notify.
            guard pct >= Self.warnUsageFloor else { return .warmingUp }
            return .willHit(beforeReset: max(0, timeUntilReset - timeToLimit),
                            runsOutIn: max(0, timeToLimit))
        }
        // Ahead of pace: your allowance would last this much past the reset.
        let spare = timeToLimit - timeUntilReset
        return .safe(projectedPercent: Int(min(99.0, projected).rounded()),
                     spareBeforeReset: spare,
                     runsOutIn: max(0, timeToLimit))
    }
}
