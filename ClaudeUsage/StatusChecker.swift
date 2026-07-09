import Foundation

enum ClaudeStatus {
    case operational
    case degraded(String)   // minor issues
    case outage(String)     // major or critical

    var isHealthy: Bool {
        if case .operational = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .operational:       return "All Systems Operational"
        case .degraded(let msg): return msg
        case .outage(let msg):   return msg
        }
    }
}

class StatusChecker {
    var onStatusReceived: ((ClaudeStatus) -> Void)?
    private var timer: Timer?

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        guard let url = URL(string: "https://status.claude.com/api/v2/status.json") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let statusObj = json["status"] as? [String: Any],
                let indicator = statusObj["indicator"] as? String,
                let description = statusObj["description"] as? String
            else { return }

            let status: ClaudeStatus
            switch indicator {
            case "none":   status = .operational
            case "minor":  status = .degraded(description)
            default:       status = .outage(description)
            }

            DispatchQueue.main.async {
                self?.onStatusReceived?(status)
            }
        }.resume()
    }

    deinit { timer?.invalidate() }
}
