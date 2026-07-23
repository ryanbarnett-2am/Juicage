import Foundation
import Combine
import AppKit

class UsageViewModel: ObservableObject {
    // One entry per workspace the login belongs to (personal, work, …).
    @Published var workspaces: [WorkspaceUsage] = []

    @Published var isLoading = false
    @Published var needsLogin = false
    @Published var errorMessage: String? = nil
    @Published var claudeStatus: ClaudeStatus = .operational

    private var fetcher: UsageFetcher!
    private var statusChecker: StatusChecker!
    private let forecaster = UsageForecaster()
    private var refreshTimer: Timer?
    private var fetchWatchdog: Timer?
    private var wakeObserver: Any?
    private var activityToken: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // Data older than this (with no successful refresh since) is considered stale.
    private let staleAfter: TimeInterval = 15 * 60

    func start() {
        fetcher = UsageFetcher()

        fetcher.onWorkspacesReceived = { [weak self] list in
            DispatchQueue.main.async { self?.apply(list) }
        }
        fetcher.onNeedsLogin = { [weak self] in
            DispatchQueue.main.async {
                self?.needsLogin = true
                self?.isLoading = false
            }
        }
        fetcher.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.errorMessage = message   // keep last good workspaces on screen
                self?.isLoading = false
            }
        }

        statusChecker = StatusChecker()
        statusChecker.onStatusReceived = { [weak self] status in
            DispatchQueue.main.async { self?.claudeStatus = status }
        }
        statusChecker.start()

        // Ask macOS not to "App Nap" us — otherwise a backgrounded menu bar app
        // gets throttled and the refresh timer can quietly stop firing.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Periodically checking Claude usage")

        // The fetcher does its first fetch automatically once the page loads.
        scheduleRefreshTimer()

        // Reschedule if the user changes the refresh interval in Preferences.
        Preferences.shared.$refreshMinutes
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefreshTimer() }
            .store(in: &cancellables)

        // After the Mac wakes from sleep, refresh right away — that's when the
        // parked page most often needs recovering.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    // Builds the refresh timer using the interval from Preferences, and adds it
    // in `.common` mode so it keeps firing even while a menu is open — and isn't
    // limited to the default run-loop mode that App Nap can suspend.
    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Preferences.shared.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        isLoading = true
        fetcher.fetch()

        // Safety net: never let the spinner hang. If nothing comes back in 25s,
        // stop loading so the "stale" cue shows and the next cycle can retry.
        fetchWatchdog?.invalidate()
        let watchdog = Timer(timeInterval: 25, repeats: false) { [weak self] _ in
            guard let self, self.isLoading else { return }
            self.isLoading = false
            if self.workspaces.isEmpty && self.errorMessage == nil {
                self.errorMessage = "No response from claude.ai — will retry."
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        fetchWatchdog = watchdog
    }

    func loggedIn() {
        needsLogin = false
        refresh()
    }

    // Store fresh data and attach a burn-rate forecast to each limit. The
    // forecaster keeps a separate history per workspace + metric.
    private func apply(_ list: [WorkspaceUsage]) {
        workspaces = list.map { ws in
            var updated = ws
            let scope = ws.id
            updated.session = forecasted(ws.session, scope: scope)
            updated.weeklyAll = forecasted(ws.weeklyAll, scope: scope)
            updated.weeklyModels = ws.weeklyModels.map { forecasted($0, scope: scope) ?? $0 }
            return updated
        }
        NotificationManager.shared.evaluate(workspaces)
        isLoading = false
        needsLogin = false
        errorMessage = nil
    }

    private func forecasted(_ metric: UsageMetric?, scope: String) -> UsageMetric? {
        guard var m = metric else { return nil }
        m.forecast = forecaster.update(key: "\(scope).\(m.key)", percent: m.percent, resetAt: m.resetAt)
        return m
    }

    // MARK: - Menu bar helpers

    // The outer ring shows the highest session usage across workspaces…
    var ringPercent: Int? {
        workspaces.compactMap { $0.session?.percent }.max()
    }

    // …and the inner ring shows the highest weekly (all models) usage.
    var weeklyRingPercent: Int? {
        workspaces.compactMap { $0.weeklyAll?.percent }.max()
    }

    // True if any limit anywhere is on pace to hit its cap — drives ⚠ + red ring.
    var isAnyAlerting: Bool {
        workspaces.contains { ws in ws.allMetrics.contains { $0.forecast.isAlerting } }
    }

    var lastUpdated: Date? {
        workspaces.compactMap { $0.lastUpdated }.max()
    }

    // True when we have data but haven't successfully refreshed it in a while —
    // e.g. offline, logged out, or the API changed. Drives the "stale" cue.
    var isStale: Bool {
        guard let last = lastUpdated else { return false }
        return Date().timeIntervalSince(last) > staleAfter
    }

    var lastUpdatedText: String {
        guard let date = lastUpdated else { return "Never" }
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "Just now" }
        return "\(Int(secs / 60)) min ago"
    }

    deinit {
        refreshTimer?.invalidate()
        fetchWatchdog?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}
