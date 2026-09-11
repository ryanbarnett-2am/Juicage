import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var loginWindow: NSWindow?
    private var settingsWindow: NSWindow?
    let viewModel = UsageViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var labelTimer: Timer?

    // Sparkle quits the app to swap the bundle, and a normal Quit is no
    // different. Either way the last few seconds of history are still sitting
    // in a pending write, so force it out before we go.
    func applicationWillTerminate(_ notification: Notification) {
        UsageHistory.shared.flush()
    }

    // Reclaim the container left behind when the App Sandbox was removed.
    //
    // Sandboxed builds kept everything under ~/Library/Containers/<bundle id>.
    // Turning the sandbox off (needed to read Ollama's log and run `lms`) moved
    // all of that to the normal locations and stranded the old copy — half a
    // gigabyte on a machine that had been running Juicage since July, which
    // nothing will ever read again.
    //
    // Guarded on actually being unsandboxed: build with ENABLE_APP_SANDBOX=YES
    // and that directory is the live home folder, so deleting it would destroy
    // the running app's own data.
    private func reclaimOrphanedContainer() {
        guard !NSHomeDirectory().contains("/Library/Containers/") else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let key = "didReclaimSandboxContainer"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)", isDirectory: true)

        DispatchQueue.global(qos: .utility).async {
            defer { UserDefaults.standard.set(true, forKey: key) }
            guard FileManager.default.fileExists(atPath: container.path) else { return }
            do {
                try FileManager.default.removeItem(at: container)
                dlog("Reclaimed orphaned sandbox container")
            } catch {
                dlog("Could not reclaim container: \(error.localizedDescription)")
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reclaimOrphanedContainer()

        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        UsageParser.runSelfTest()
        MenuBarTitle.runSelfTest()
        #endif
        NotificationManager.shared.requestAuthorization()
        _ = UpdateController.shared     // starts Sparkle's scheduled check, if present
        setupStatusBar()
        setupPopover()
        observeViewModel()
        viewModel.start()

        // Let the popover's "Sign In" button (re)open the login window.
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenLogin),
                                               name: .openLogin, object: nil)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.title = " …"
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(viewModel)
        )
    }

    private func observeViewModel() {
        // Rebuild the menu bar whenever the usage data or Claude's status changes.
        // A 60s timer also refreshes it so the countdown ticks down between the
        // 3-minute data fetches.
        Publishers.CombineLatest(viewModel.$workspaces, viewModel.$claudeStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateStatusBar() }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateStatusBar()
        }
        RunLoop.main.add(timer, forMode: .common)
        labelTimer = timer

        // A local model starting or finishing changes the menu bar dot.
        viewModel.$localJobs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }
            .store(in: &cancellables)

        // Redraw the menu bar immediately when the "show percentage" setting changes.
        Preferences.shared.$showMenuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }
            .store(in: &cancellables)
        Preferences.shared.$showEndTimes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }
            .store(in: &cancellables)
        Preferences.shared.$menuBarMetrics
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }
            .store(in: &cancellables)
        Preferences.shared.$menuBarLabelStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }
            .store(in: &cancellables)

        viewModel.$needsLogin
            .receive(on: RunLoop.main)
            .sink { [weak self] needs in
                if needs {
                    self?.statusItem.button?.title = " Sign in"
                    self?.showLoginWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }

        let alert = viewModel.isAnyAlerting
        let title = MenuBarTitle.make(workspaces: viewModel.workspaces,
                                      keys: Preferences.shared.menuBarMetrics,
                                      labels: Preferences.shared.menuBarLabelStyle,
                                      showEndTimes: Preferences.shared.showEndTimes)

        // The ring is the primary indicator; the outage dot only appears on top
        // of it when Claude itself is having problems.
        let text = Preferences.shared.showMenuBarText && !title.isEmpty
            ? (alert ? "\(title) ⚠" : title)
            : ""                // ring only (saves menu bar space, e.g. on notched Macs)

        // A green dot trails the text while a local model is generating. It's
        // deliberately separate from the rings: local models have no quota, just
        // a busy state, so it says "working" and nothing more.
        if viewModel.isLocalBusy {
            button.attributedTitle = busyTitle(text)
        } else {
            button.title = text
        }
        button.image = ringOrStatusImage()
        button.imagePosition = .imageLeft

        // Dim the whole item when the data hasn't refreshed in a while, so old
        // numbers don't look live.
        button.appearsDisabled = viewModel.isStale
    }

    // Menu bar text with a green "busy" dot appended, sized to sit level with
    // the numbers rather than dominating them.
    private func busyTitle(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text.isEmpty ? "" : "\(text) ")
        out.append(NSAttributedString(string: "●", attributes: [
            .foregroundColor: NSColor.systemGreen,
            .font: NSFont.systemFont(ofSize: 9),
        ]))
        return out
    }

    // The ring, unless Claude is down — then show the outage dot instead.
    private func ringOrStatusImage() -> NSImage {
        if !viewModel.claudeStatus.isHealthy {
            return statusDotImage(for: viewModel.claudeStatus)
        }
        return ProgressRingImage.make(session: viewModel.ringPercent,
                                      sessionSeverity: viewModel.sessionSeverity,
                                      weekly: viewModel.weeklyRingPercent,
                                      weeklySeverity: viewModel.weeklySeverity)
    }

    private func statusDotImage(for status: ClaudeStatus) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let color: NSColor
            if case .outage = status { color = .systemRed } else { color = .systemOrange }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8)).fill()
            return true
        }
    }

    // MARK: - Click handling

    // Left-click opens the popover; right-click shows the context menu.
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // "Juicage 1.6.2" — disabled, purely a label. Version confusion is the first
    // thing that comes up whenever someone reports a problem, so it's worth the
    // zero clicks it takes to read it here.
    private var versionMenuItem: NSMenuItem {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let item = NSMenuItem(title: "Juicage \(short)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(versionMenuItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let openPage = NSMenuItem(title: "Open Usage Page in Browser", action: #selector(menuOpenPage), keyEquivalent: "")
        openPage.target = self
        menu.addItem(openPage)

        let signIn = NSMenuItem(title: "Sign in to Claude…", action: #selector(menuSignIn), keyEquivalent: "")
        signIn.target = self
        menu.addItem(signIn)

        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launch)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(menuPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = UpdateController.shared.canCheckForUpdates
        menu.addItem(update)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Juicage", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Juicage", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach the menu just for this click, then detach so left-click still
        // opens the popover next time.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuRefresh() { viewModel.refresh() }
    @objc private func menuSignIn()  { showLoginWindow() }
    @objc private func menuQuit()    { NSApp.terminate(nil) }

    @objc private func menuOpenPage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func menuAbout() {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        // An accessory app has no menu bar of its own, so the panel opens behind
        // everything unless we activate first.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Juicage",
            .applicationVersion: short,
            .version: build,
            .init(rawValue: "Copyright"): "An unofficial usage meter for claude.ai.\nNot affiliated with Anthropic.",
        ])
    }

    @objc private func menuCheckForUpdates() {
        UpdateController.shared.checkForUpdates()
    }

    @objc private func menuToggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func menuPreferences() {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(viewModel))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Juicage Preferences"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLoginWindow() {
        // Become a regular app while signing in: this gives a Dock icon (click it
        // to bring the window back if it slips behind your browser) and reliable
        // mouse/keyboard input. We revert to menu-bar-only when done.
        // NOTE: deliberately NOT a floating window — a WKWebView at an elevated
        // window level doesn't reliably receive clicks.
        NSApp.setActivationPolicy(.regular)

        if loginWindow == nil {
            let view = LoginView(onLoggedIn: { [weak self] in
                self?.finishLogin()
            })
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Sign in to Claude"
            win.styleMask = [.titled, .closable, .resizable]
            win.setContentSize(NSSize(width: 480, height: 640))
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            loginWindow = win
        }
        loginWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishLogin() {
        loginWindow?.orderOut(nil)
        loginWindow = nil
        NSApp.setActivationPolicy(.accessory)   // back to menu-bar-only
        viewModel.loggedIn()
    }

    @objc private func handleOpenLogin() {
        showLoginWindow()
    }

    // If the user closes the sign-in window without finishing, revert to
    // menu-bar-only so we don't leave a stray Dock icon behind.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as AnyObject) === loginWindow {
            loginWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension Notification.Name {
    // Posted by the popover's "Sign In" button to (re)open the login window.
    static let openLogin = Notification.Name("JuicageOpenLogin")
}

// MARK: - Menu bar text

// Builds the text beside the ring from whichever limits you picked in
// Preferences. Pure, so the self-test below can check it without a menu bar.
enum MenuBarTitle {
    static func make(workspaces: [WorkspaceUsage], keys: [String],
                     labels: MenuBarLabelStyle, showEndTimes: Bool,
                     now: Date = Date()) -> String {
        guard !workspaces.isEmpty else { return " …" }
        let selected = Set(keys)
        // A label only earns its space once there's more than one number to
        // tell apart — one limit reads fine as a bare percentage, as it always
        // has. Past that it's a trade against menu bar width, which is what
        // the style is for.
        let style: MenuBarLabelStyle = selected.count > 1 ? labels : .off

        var parts: [String] = []
        for ws in workspaces {
            let shown = ws.allMetrics.filter { selected.contains($0.key) }
            if shown.isEmpty {
                // Keep a placeholder so several accounts still line up left to right.
                if workspaces.count > 1 { parts.append("—") }
                continue
            }
            parts.append(contentsOf: shown.map { $0.menuBarText(style) })
        }
        guard !parts.isEmpty else { return "" }   // nothing picked → ring only

        var title = " " + parts.joined(separator: style.separator)
        // Only the session gets a countdown. A weekly cap resets days out, and
        // "163h0m" next to a percentage isn't something anyone acts on.
        if selected.contains("session"),
           let reset = workspaces.compactMap({ $0.session })
               .max(by: { $0.percent < $1.percent })?.resetAt,
           reset.timeIntervalSince(now) > 0 {
            title += " · " + (showEndTimes ? DateUtils.shortClock(reset)
                                           : DateUtils.shortCountdown(to: reset, now: now))
        }
        return title
    }

    // MARK: - Self-test

    // Checks the shapes that are easy to break: the default selection has to
    // look exactly like it did before this setting existed, and adding limits
    // must not start printing a weekly countdown. Debug builds only.
    #if DEBUG
    static func runSelfTest() {
        let now = Date()
        var ws = WorkspaceUsage()
        ws.session = UsageMetric(key: "session", label: "Current Session",
                                 percent: 42, resetAt: now.addingTimeInterval(3600))
        ws.weeklyAll = UsageMetric(key: "weekly_all", label: "All Models", percent: 71)
        ws.weeklyModels = [UsageMetric(key: "weekly_scoped:Fable", label: "Fable", percent: 12)]
        var other = WorkspaceUsage()
        other.session = UsageMetric(key: "session", label: "Current Session",
                                    percent: 88, resetAt: now.addingTimeInterval(7200))

        var problems: [String] = []
        func check(_ what: String, _ keys: [String], _ list: [WorkspaceUsage], _ want: String,
                   labels: MenuBarLabelStyle = .full) {
            let got = make(workspaces: list, keys: keys, labels: labels,
                           showEndTimes: false, now: now)
            if got != want { problems.append("\(what): expected \"\(want)\", got \"\(got)\"") }
        }

        check("default (session only)", ["session"], [ws], " 42% · 1h0m")
        check("session + week", ["session", "weekly_all"], [ws],
              " Session 42% · Week 71% · 1h0m")
        check("week + model, no countdown", ["weekly_all", "weekly_scoped:Fable"], [ws],
              " Week 71% · Fable 12%")
        // The two narrower styles, on the widest case they have to fix.
        let all = ["session", "weekly_all", "weekly_scoped:Fable"]
        check("all three, initials", all, [ws], " C:42% W:71% F:12% · 1h0m", labels: .initial)
        check("all three, percent only", all, [ws], " 42% · 71% · 12% · 1h0m", labels: .off)
        // One limit has nothing to disambiguate, so every style reads the same.
        for style in MenuBarLabelStyle.allCases {
            check("one limit, \(style.rawValue)", ["session"], [ws], " 42% · 1h0m", labels: style)
        }
        check("nothing selected", [], [ws], "")
        check("limit the account doesn't have", ["weekly_scoped:Nope"], [ws], "")
        // The countdown follows the busiest session — the one the ring reflects.
        check("two accounts", ["session"], [ws, other], " 42% · 88% · 2h0m")
        check("account missing the limit", ["weekly_all"], [ws, other], " 71% · —")
        check("no data yet", ["session"], [], " …")

        if problems.isEmpty {
            dlog("menu bar title self-test PASSED ✓")
        } else {
            dlog("menu bar title self-test FAILED ✗ — \(problems.joined(separator: "; "))")
        }
    }
    #endif
}
