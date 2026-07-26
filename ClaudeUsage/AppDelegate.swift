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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        UsageParser.runSelfTest()
        #endif
        NotificationManager.shared.requestAuthorization()
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

        // Redraw the menu bar immediately when the "show percentage" setting changes.
        Preferences.shared.$showMenuBarText
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

        let workspaces = viewModel.workspaces
        let alert = viewModel.isAnyAlerting
        let title: String

        if workspaces.isEmpty {
            title = " …"
        } else if workspaces.count == 1, let session = workspaces[0].session {
            // Single account: show % plus a compact countdown.
            var s = " \(session.percent)%"
            if let reset = session.resetAt, reset.timeIntervalSinceNow > 0 {
                s += " · \(DateUtils.shortCountdown(to: reset))"
            }
            title = s
        } else {
            // Multiple accounts: show each session %, then the countdown for
            // whichever session is highest — the one the ring reflects — so time
            // left stays visible instead of being dropped.
            let parts = workspaces.map { ws in ws.session.map { "\($0.percent)%" } ?? "—" }
            var s = " " + parts.joined(separator: " · ")
            if let busiest = workspaces.compactMap({ $0.session })
                .max(by: { $0.percent < $1.percent }),
               let reset = busiest.resetAt, reset.timeIntervalSinceNow > 0 {
                s += " · \(DateUtils.shortCountdown(to: reset))"
            }
            title = s
        }

        // The ring is the primary indicator; the outage dot only appears on top
        // of it when Claude itself is having problems.
        if Preferences.shared.showMenuBarText {
            button.title = alert ? "\(title) ⚠" : title
        } else {
            button.title = ""   // ring only (saves menu bar space, e.g. on notched Macs)
        }
        button.image = ringOrStatusImage()
        button.imagePosition = .imageLeft

        // Dim the whole item when the data hasn't refreshed in a while, so old
        // numbers don't look live.
        button.appearsDisabled = viewModel.isStale
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

    private func showContextMenu() {
        let menu = NSMenu()

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

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Tally", action: #selector(menuQuit), keyEquivalent: "q")
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

    @objc private func menuToggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func menuPreferences() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "Tally Preferences"
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
    static let openLogin = Notification.Name("TallyOpenLogin")
}
