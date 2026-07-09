import Foundation

// Projects whether a limit will be hit before it resets, using the utilization
// readings gathered on each poll. Pure in-memory — a reset clears the history.
//
// Strategy: prefer the *observed* burn rate over the last ~15 minutes (reflects
// what you're doing right now). Before there's enough history, fall back to the
// average pace since the limit's window opened. Then it's simply:
//     timeToLimit = (100 - current%) / rate   vs.   time until reset.
// It's a linear projection — usage is bursty, so treat it as a trend signal,
// not a precise ETA. It relaxes back to "safe" as soon as you idle.
final class UsageForecaster {
    private struct Sample { let t: Date; let pct: Double }
    private var series: [String: [Sample]] = [:]

    private let lookback: TimeInterval = 15 * 60   // measure recent rate over this span
    private let minSpan: TimeInterval = 3 * 60     // need this much history for an observed rate
    private let maxSamples = 60

    // How long each kind of limit's window is, used for the average-pace fallback.
    // Keys may be workspace-prefixed (e.g. "org123.session"), so match the suffix.
    static func windowLength(forKey key: String) -> TimeInterval {
        key.hasSuffix("session") ? 5 * 60 * 60 : 7 * 24 * 60 * 60
    }

    func update(key: String, percent: Int?, resetAt: Date?,
                now: Date = Date()) -> ForecastVerdict {
        guard let pctInt = percent, let resetAt else { return .unknown }
        let pct = Double(pctInt)
        let windowLength = Self.windowLength(forKey: key)

        var samples = series[key] ?? []
        // A drop in utilization means the window reset — start the series over.
        if let last = samples.last, pct < last.pct - 1 { samples.removeAll() }
        samples.append(Sample(t: now, pct: pct))
        samples = samples.filter { now.timeIntervalSince($0.t) <= lookback }
        if samples.count > maxSamples { samples = Array(samples.suffix(maxSamples)) }
        series[key] = samples

        let timeUntilReset = resetAt.timeIntervalSince(now)
        guard timeUntilReset > 0 else { return .unknown }
        if pct >= 100 { return .atLimit }

        guard let rate = burnRate(samples: samples, now: now, resetAt: resetAt,
                                  windowLength: windowLength, current: pct) else {
            return .unknown
        }
        // Idle → usage stays put, so there's no meaningful time margin.
        if rate <= 1e-7 { return .safe(projectedPercent: pctInt, spareBeforeReset: nil) }

        // How long until you'd hit 100% at the current rate, vs. time until reset.
        let timeToLimit = (100.0 - pct) / rate
        if timeToLimit < timeUntilReset {
            // You run out this much time *before* the reset — behind pace.
            return .willHit(beforeReset: timeUntilReset - timeToLimit)
        }
        // You reset before running out — ahead of pace by this much time.
        let spare = timeToLimit - timeUntilReset
        let projected = pct + rate * timeUntilReset
        return .safe(projectedPercent: Int(min(99.0, projected).rounded()), spareBeforeReset: spare)
    }

    // Percent-per-second. Observed recent rate when we have enough history,
    // otherwise the average pace since the window opened.
    private func burnRate(samples: [Sample], now: Date, resetAt: Date,
                          windowLength: TimeInterval, current: Double) -> Double? {
        if let first = samples.first, let last = samples.last {
            let dt = last.t.timeIntervalSince(first.t)
            if dt >= minSpan { return max(0, (last.pct - first.pct) / dt) }
        }
        let windowStart = resetAt.addingTimeInterval(-windowLength)
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed > 0 { return current / elapsed }
        return nil
    }
}
