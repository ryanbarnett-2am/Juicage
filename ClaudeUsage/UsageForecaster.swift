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

    // Stateless — average pace needs only the current reading, not history.
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

        // Average pace projected to the reset: projected = pct / windowFraction.
        let windowFraction = elapsed / windowLength
        let ratePerSec = pct / elapsed                 // percent per second
        let projected = pct / windowFraction
        let timeToLimit = (100.0 - pct) / ratePerSec   // from now, at average pace

        if projected >= 100 {
            // On pace to run out — but only sound the alarm once enough of the
            // budget is actually gone that it's real, not an early-prompt mirage.
            // Below the floor we're still "warming up": show it's calculating,
            // but don't alarm or notify.
            guard pct >= Self.warnUsageFloor else { return .warmingUp }
            return .willHit(beforeReset: max(0, timeUntilReset - timeToLimit))
        }
        // Ahead of pace: your allowance would last this much past the reset.
        let spare = timeToLimit - timeUntilReset
        return .safe(projectedPercent: Int(min(99.0, projected).rounded()),
                     spareBeforeReset: spare)
    }
}
