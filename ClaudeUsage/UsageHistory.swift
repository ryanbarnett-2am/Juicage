import Foundation

// One limit window — a five-hour session, a seven-day cap — and the highest
// percentage reached inside it.
//
// Storing the peak per window rather than every reading is both far smaller and
// closer to the question people actually ask. "Did I run out this week?" is
// answered by the peak; the shape of the climb isn't. A year is roughly 1,750
// session windows and 52 weekly ones, which is a small JSON file rather than a
// database.
struct UsageWindow: Codable, Equatable, Identifiable {
    let providerID: String
    let metricKey: String
    let resetAt: Date          // identifies the window: each one resets exactly once
    var peakPercent: Int
    var lastSeen: Date

    var id: String { "\(providerID)|\(metricKey)|\(resetAt.timeIntervalSince1970)" }
}

// Records usage history and reads it back as a series.
//
// History cannot be backfilled — a day not recorded is gone — so this runs from
// the moment the app launches, independent of anything drawing it.
final class UsageHistory {
    static let shared = UsageHistory()

    // Keep about a year. Old windows answer "which plan suits me" no better than
    // recent ones, and the file should stay something you can open and read.
    private static let maxWindowsPerMetric = 400

    private var windows: [String: UsageWindow] = [:]   // keyed by UsageWindow.id
    private let queue = DispatchQueue(label: "tally.history")
    private var saveScheduled = false

    private lazy var fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        // Keyed by the bundle identifier, like the rest of the app's state.
        let dir = base.appendingPathComponent("twoam.Tally", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        let collapsed = load()
        // Writing back only happens when a peak rises, so a load that merged
        // legacy duplicates would otherwise sit un-persisted indefinitely —
        // correct in memory, still wrong on disk, and wrong again next launch.
        if collapsed { scheduleSave() }
    }

    // MARK: - Recording

    // Called on every refresh. Upserts the current window for each limit, raising
    // its peak. A metric with no reset time (the API sometimes omits one) can't
    // be attributed to a window, so it's skipped rather than guessed at.
    // The API returns a window's reset time a second or two apart between
    // fetches — 15:59:59 on one poll, 16:00:00 on the next. Keyed on the exact
    // timestamp those become separate windows, so a single week gets counted
    // repeatedly and "last 8" shows the same week over and over. Snapping to the
    // minute collapses them; real windows are hours apart, so nothing distinct
    // can collide.
    private func canonical(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    func record(_ workspaces: [WorkspaceUsage], now: Date = Date()) {
        var changed = false
        for workspace in workspaces {
            for metric in workspace.allMetrics {
                guard let rawReset = metric.resetAt else { continue }
                let resetAt = canonical(rawReset)
                let window = UsageWindow(providerID: workspace.providerID,
                                         metricKey: metric.key,
                                         resetAt: resetAt,
                                         peakPercent: metric.percent,
                                         lastSeen: now)
                if var existing = windows[window.id] {
                    guard metric.percent > existing.peakPercent else { continue }
                    existing.peakPercent = metric.percent
                    existing.lastSeen = now
                    windows[window.id] = existing
                } else {
                    windows[window.id] = window
                }
                changed = true
            }
        }
        if changed { prune(); scheduleSave() }
    }

    // MARK: - Reading

    // Peaks for the most recent windows of one limit, oldest first — the shape a
    // sparkline draws. Excludes the window still in progress, whose peak is only
    // "so far" and would always read as a dip at the right-hand edge.
    func series(providerID: String, metricKey: String,
                limit: Int = 12, now: Date = Date()) -> [Int] {
        windows.values
            .filter { $0.providerID == providerID && $0.metricKey == metricKey && $0.resetAt <= now }
            .sorted { $0.resetAt < $1.resetAt }
            .suffix(limit)
            .map(\.peakPercent)
    }

    // How many of the last `limit` completed windows were exhausted — the number
    // behind "you hit your weekly limit in 3 of the last 8 weeks".
    func timesMaxed(providerID: String, metricKey: String,
                    limit: Int = 12, now: Date = Date()) -> (hit: Int, of: Int) {
        let s = series(providerID: providerID, metricKey: metricKey, limit: limit, now: now)
        return (s.filter { $0 >= 100 }.count, s.count)
    }

    // Whole window records overlapping a time range, oldest first — what the day
    // strip needs, since it positions each window by when it actually ran rather
    // than just how full it got.
    func windows(providerID: String, metricKey: String,
                 from: Date, to: Date, windowLength: TimeInterval) -> [UsageWindow] {
        windows.values
            .filter { w in
                guard w.providerID == providerID, w.metricKey == metricKey else { return false }
                let opened = w.resetAt.addingTimeInterval(-windowLength)
                return w.resetAt > from && opened < to      // any overlap with the range
            }
            .sorted { $0.resetAt < $1.resetAt }
    }

    // Average share of each window left unused — the capacity you paid for and
    // didn't spend. The mirror of the peak: 45% average use means 55% expired.
    func averageUnused(providerID: String, metricKey: String,
                       limit: Int = 12, now: Date = Date()) -> Int? {
        let s = series(providerID: providerID, metricKey: metricKey, limit: limit, now: now)
        guard !s.isEmpty else { return nil }
        let usedAvg = Double(s.reduce(0, +)) / Double(s.count)
        return Int((100 - usedAvg).rounded())
    }

    // MARK: - Storage

    private func prune() {
        var byMetric: [String: [UsageWindow]] = [:]
        for w in windows.values {
            byMetric["\(w.providerID)|\(w.metricKey)", default: []].append(w)
        }
        var kept: [String: UsageWindow] = [:]
        for (_, list) in byMetric {
            for w in list.sorted(by: { $0.resetAt < $1.resetAt })
                        .suffix(Self.maxWindowsPerMetric) {
                kept[w.id] = w
            }
        }
        windows = kept
    }

    // Writing on every refresh would be harmless at this size, but coalescing
    // keeps the disk quiet when several providers report in quick succession.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveScheduled = false
            self?.save()
        }
    }

    private func save() {
        let snapshot = Array(windows.values).sorted { $0.resetAt < $1.resetAt }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]   // readable if anyone opens it
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // Returns true when normalising merged records together, so the caller can
    // persist the cleaned-up store.
    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([UsageWindow].self, from: data) else { return false }
        // Canonicalise on the way in as well as out. Snapping only on write left
        // records saved by older builds keyed to their original second, so they
        // survived forever and every new reading created a second entry for the
        // same window — the duplicates came straight back.
        for w in list {
            var normalised = w
            normalised = UsageWindow(providerID: w.providerID, metricKey: w.metricKey,
                                     resetAt: canonical(w.resetAt),
                                     peakPercent: w.peakPercent, lastSeen: w.lastSeen)
            if let existing = windows[normalised.id] {
                // Two legacy rows can collapse onto one window; keep the higher peak.
                if normalised.peakPercent > existing.peakPercent { windows[normalised.id] = normalised }
            } else {
                windows[normalised.id] = normalised
            }
        }
        return windows.count != list.count
    }

    // Where the file lives, for a "Reveal in Finder" affordance later.
    var storeURL: URL { fileURL }
}
