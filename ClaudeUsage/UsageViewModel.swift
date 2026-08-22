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

    // Local models (Ollama / LM Studio) working right now — separate from the
    // claude.ai numbers above, since these have no quota, just a busy/idle state.
    @Published var localJobs: [LocalJob] = []

    // Jobs finished so far in the current burst — shown in the popover so a long
    // batch reads as progress rather than a single stuck-looking row.
    @Published var localCompleted = 0

    // Held slightly past the last job so a batch of short calls doesn't strobe.
    @Published var localBusy = false

    private var fetcher: UsageFetcher!
    private var statusChecker: StatusChecker!
    private let localMonitor = LocalLLMMonitor()
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

        // Local model watcher. Publishes its own list and tells us when a job
        // ends so we can fire the "finished" notification.
        localMonitor.onRunFinished = { [weak self] run in
            guard let self, Preferences.shared.notifyLocalDone else { return }
            NotificationManager.shared.localRunFinished(run)
        }
        localMonitor.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs in self?.localJobs = jobs }
            .store(in: &cancellables)
        localMonitor.$completedInRun
            .receive(on: RunLoop.main)
            .sink { [weak self] count in self?.localCompleted = count }
            .store(in: &cancellables)
        localMonitor.$isBusy
            .receive(on: RunLoop.main)
            .sink { [weak self] busy in self?.localBusy = busy }
            .store(in: &cancellables)
        applyLocalPreference(Preferences.shared.watchLocalLLMs)
        Preferences.shared.$watchLocalLLMs
            .dropFirst()
            .sink { [weak self] on in self?.applyLocalPreference(on) }
            .store(in: &cancellables)

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

    private func applyLocalPreference(_ enabled: Bool) {
        if enabled {
            localMonitor.start()
        } else {
            localMonitor.stop()
            localJobs = []
            localBusy = false
            localCompleted = 0
        }
    }

    // True while local work is in progress — drives the menu bar indicator.
    var isLocalBusy: Bool { localBusy }

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

    // True if any limit anywhere is on pace to hit its cap — drives the ⚠ text.
    var isAnyAlerting: Bool {
        workspaces.contains { ws in ws.allMetrics.contains { $0.forecast.isAlerting } }
    }

    // Per-ring severity, so the outer (session) and inner (weekly) rings color
    // independently (and get the orange middle tier), instead of both jumping to
    // red when only one is in trouble. Takes the worst across workspaces.
    var sessionSeverity: Severity {
        workspaces.compactMap { $0.session }
            .map { severity(percent: $0.percent, forecast: $0.forecast) }.max() ?? .ok
    }
    var weeklySeverity: Severity {
        workspaces.compactMap { $0.weeklyAll }
            .map { severity(percent: $0.percent, forecast: $0.forecast) }.max() ?? .ok
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
        localMonitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}
