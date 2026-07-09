import ServiceManagement

// Thin wrapper around macOS's login-item API so the app can add or remove
// itself from "Open at Login" (System Settings → General → Login Items).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            dlog("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
