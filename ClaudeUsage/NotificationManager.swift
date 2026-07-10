import Foundation
import UserNotifications

// Sends a macOS notification when a limit crosses a threshold (80% / 100%) or a
// forecast turns to "on pace to hit the limit." It remembers what it has already
// told you per limit, so it fires once per event — not every 3-minute refresh —
// and re-arms when a limit resets.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    // What we've already notified about, per "workspace.metric" key.
    private struct State {
        var lastPercent: Int
        var notifiedLevel: Int    // highest % threshold already announced (0/80/100)
        var forecastFired: Bool
    }
    private var states: [String: State] = [:]

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func evaluate(_ workspaces: [WorkspaceUsage]) {
        guard authorized else { return }
        let showName = workspaces.count > 1
        for ws in workspaces {
            for metric in ws.allMetrics {
                evaluate(metric, workspace: ws, showName: showName)
            }
        }
    }

    private func evaluate(_ metric: UsageMetric, workspace: WorkspaceUsage, showName: Bool) {
        let key = "\(workspace.id).\(metric.key)"
        var state = states[key] ?? State(lastPercent: metric.percent, notifiedLevel: 0, forecastFired: false)

        // A drop in usage means the limit reset — re-arm all alerts for it.
        if metric.percent < state.lastPercent - 1 {
            state.notifiedLevel = 0
            state.forecastFired = false
        }

        let prefix = (showName ? (workspace.workspaceName.map { "\($0) · " } ?? "") : "")

        // Percentage thresholds
        let level = metric.percent >= 100 ? 100 : (metric.percent >= 80 ? 80 : 0)
        if level > state.notifiedLevel {
            if level == 100 {
                notify(title: "Claude limit reached",
                       body: "\(prefix)\(metric.label) is at 100%.")
            } else {
                notify(title: "Claude usage high",
                       body: "\(prefix)\(metric.label) is at \(metric.percent)%.")
            }
            state.notifiedLevel = level
        }

        // Forecast: on pace to hit the limit before it resets
        if metric.forecast.isAlerting && !state.forecastFired {
            if case .willHit(let before) = metric.forecast {
                notify(title: "On pace to hit a limit",
                       body: "\(prefix)\(metric.label): on pace to run out ~\(DateUtils.duration(before)) before it resets.")
                state.forecastFired = true
            }
        }

        state.lastPercent = metric.percent
        states[key] = state
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    // Show notifications even while the (accessory) app is running.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
