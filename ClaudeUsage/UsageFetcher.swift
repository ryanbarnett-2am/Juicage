import WebKit

// Keeps a hidden WKWebView parked on claude.ai so it can call the site's own
// usage API using your logged-in cookies. This is NOT web scraping — we ask
// claude.ai for the same structured data its own settings page uses:
//
//     GET /api/organizations               -> your workspaces
//     GET /api/organizations/{id}/usage    -> usage numbers as clean JSON
//
// The JavaScript below runs those two calls and hands the result back to Swift
// through a "message handler" — a little mailbox WebKit gives us for exactly
// this purpose.
final class UsageFetcher: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let webView: WKWebView
    private let offscreenWindow: NSWindow

    var onWorkspacesReceived: (([WorkspaceUsage]) -> Void)?
    var onNeedsLogin: (() -> Void)?
    var onError: ((String) -> Void)?

    private var pageReady = false
    private var isReloading = false
    private var reloadTimer: Timer?

    // Which cookie jar this fetcher signs in against. One per account.
    private let dataStore: WKWebsiteDataStore

    init(dataStore: WKWebsiteDataStore = .default()) {
        self.dataStore = dataStore
        // A message handler named "usage" is the mailbox the JS posts into.
        let userContent = WKUserContentController()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore   // this account's login cookies
        config.userContentController = userContent

        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        webView = WKWebView(frame: frame, configuration: config)

        // WebKit only runs a page's JavaScript timers if the web view lives in a
        // real on-screen window — so we give it one, parked far off-screen and
        // fully transparent. You never see it.
        offscreenWindow = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        offscreenWindow.contentView = webView
        offscreenWindow.alphaValue = 0
        offscreenWindow.ignoresMouseEvents = true
        offscreenWindow.orderBack(nil)

        super.init()

        userContent.add(self, name: "usage")
        webView.navigationDelegate = self

        // Park on the claude.ai origin once; after that we just re-run the API
        // call. Any claude.ai URL works — we only need the origin + cookies.
        webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))

        // Reload the parked page every 30 minutes so the login session stays
        // fresh over long uptimes. Added in `.common` mode for the same reason
        // as the refresh timer.
        let reload = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            self?.reloadPage()
        }
        RunLoop.main.add(reload, forMode: .common)
        reloadTimer = reload
    }

    // Called every 3 minutes by the view model. If the page is parked and ready,
    // re-run the API call. If the page got into a not-ready state (e.g. an
    // interrupted reload after the Mac slept), reload it to recover instead of
    // silently doing nothing — otherwise a refresh would hang forever.
    func fetch() {
        guard pageReady else {
            dlog("fetch() called while page not ready — reloading to recover")
            reloadPage()
            return
        }
        dlog("fetch() firing on \(webView.url?.absoluteString ?? "nil")")
        webView.evaluateJavaScript(Self.fetchJS) { _, error in
            if let error = error {
                dlog("JS error: \(error.localizedDescription)")
            }
        }
    }

    // Reloads the parked page (used by the 30-min timer and by fetch() recovery).
    private func reloadPage() {
        guard !isReloading else { return }
        isReloading = true
        pageReady = false
        webView.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        isReloading = false
        // Small delay so cookies/session are settled, then do the first fetch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetch()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isReloading = false
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isReloading = false
        onError?(error.localizedDescription)
    }

    // MARK: - Receiving the JS result

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "usage",
              let payload = message.body as? [String: Any] else {
            dlog("message received but body wasn't a dictionary: \(String(describing: message.body))")
            return
        }

        if let error = payload["error"] as? String {
            dlog("payload error: \(error)")
            if error == "not_logged_in" {
                onNeedsLogin?()
            } else {
                onError?(error)
            }
            return
        }

        // The JS posts one payload containing every workspace it found.
        guard let rawWorkspaces = payload["workspaces"] as? [[String: Any]] else {
            dlog("no 'workspaces' array in payload")
            onError?("Unexpected response from claude.ai")
            return
        }

        var results: [WorkspaceUsage] = []
        for raw in rawWorkspaces {
            var ws = WorkspaceUsage()
            ws.workspaceID = raw["uuid"] as? String
            ws.workspaceName = raw["name"] as? String
            ws.lastUpdated = Date()

            if let err = raw["error"] as? String {
                ws.error = err
                results.append(ws)
                continue
            }

            if let usageDict = raw["usage"] as? [String: Any] {
                var parsed = UsageParser.parseUsage(usageDict)
                parsed.workspaceID = ws.workspaceID
                parsed.workspaceName = ws.workspaceName
                parsed.lastUpdated = ws.lastUpdated
                ws = parsed
            }
            // Only keep workspaces that actually have usage to show.
            if ws.session != nil || ws.weeklyAll != nil || !ws.weeklyModels.isEmpty {
                results.append(ws)
            }
        }

        dlog("parsed \(results.count) workspace(s): "
             + results.map { "\($0.workspaceName ?? "?") session \($0.session?.percent ?? -1)%" }.joined(separator: ", "))

        onWorkspacesReceived?(results)
    }

    deinit {
        reloadTimer?.invalidate()
    }

    // The script that actually talks to claude.ai's API. Runs inside the logged-in
    // page, so `credentials: 'include'` sends your session cookies automatically.
    private static let fetchJS = """
    (async function() {
      function post(p) { try { window.webkit.messageHandlers.usage.postMessage(p); } catch (e) {} }
      try {
        const orgs = await fetch('/api/organizations', { credentials: 'include' })
                             .then(r => r.json());
        if (!Array.isArray(orgs) || orgs.length === 0) {
          post({ error: 'not_logged_in' });
          return;
        }
        // Fetch usage for every workspace this login belongs to (personal + work).
        const workspaces = [];
        for (const org of orgs) {
          try {
            const usage = await fetch('/api/organizations/' + org.uuid + '/usage',
                                      { credentials: 'include' }).then(r => r.json());
            workspaces.push({ uuid: org.uuid, name: org.name, usage: usage });
          } catch (e) {
            workspaces.push({ uuid: org.uuid, name: org.name,
                              error: 'usage fetch failed: ' + ((e && e.message) || String(e)) });
          }
        }
        post({ workspaces: workspaces });
      } catch (e) {
        post({ error: 'API call failed: ' + ((e && e.message) || String(e)) });
      }
    })();
    undefined;
    """
}
