import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

// In-app updates via Sparkle.
//
// Deliberately compiled behind `canImport(Sparkle)` so the project still builds
// before the package has been added, and lights up on its own once it has —
// nothing else in the app needs to change either way. Until then "Check for
// Updates…" just opens the releases page, which is what people were doing by
// hand anyway.
//
// Sparkle verifies each update with an EdDSA signature (SUPublicEDKey in
// Info.plist) on top of Apple notarization, so a tampered download is rejected
// even if someone could serve it from our URL.
final class UpdateController {
    static let shared = UpdateController()

    private static let releasesURL =
        URL(string: "https://github.com/ryanbarnett-2am/Juicage/releases/latest")!

    #if canImport(Sparkle)
    // startingUpdater: true begins the scheduled background check immediately.
    // Sparkle asks the user, on first run, whether to check automatically — so
    // this doesn't phone home behind anyone's back.
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var usingSparkle: Bool { true }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // Lets the menu item disable itself while a check is already running.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    #else
    var usingSparkle: Bool { false }
    var canCheckForUpdates: Bool { true }

    func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }
    #endif
}
