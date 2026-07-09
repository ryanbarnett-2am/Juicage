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
    private var reloadTimer: Timer?

    override init() {
        // A message handler named "usage" is the mailbox the JS posts into.
        let userContent = WKUserContentController()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()  // shares the login cookies
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
            self?.pageReady = false
            self?.webView.reload()
        }
        RunLoop.main.add(reload, forMode: .common)
        reloadTimer = reload
    }

    // Called every 3 minutes by the view model. If the page is parked and ready,
    // just re-run the API call — no page reload needed.
    func fetch() {
        guard pageReady else {
            dlog("fetch() skipped — page not ready yet")
            return
        }
        dlog("fetch() firing on \(webView.url?.absoluteString ?? "nil")")
        webView.evaluateJavaScript(Self.fetchJS) { _, error in
            if let error = error {
                dlog("JS error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        // Small delay so cookies/session are settled, then do the first fetch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fetch()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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
                parseUsage(usageDict, into: &ws)
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

    // Fills one workspace's metrics from its usage JSON.
    private func parseUsage(_ usageDict: [String: Any], into result: inout WorkspaceUsage) {
        // The "limits" array is claude.ai's canonical usage structure. Each entry
        // has a `kind` (session / weekly_all / weekly_scoped), a `percent`, a
        // `resets_at`, and — for per-model caps — a `scope` naming the model.
        // Reading this array is what makes Fable and other models appear.
        if let limits = usageDict["limits"] as? [[String: Any]] {
            for limit in limits {
                guard let pct = doubleValue(limit["percent"]) else { continue }
                let percent = Int(pct.rounded())
                let resetAt = DateUtils.parseISO(limit["resets_at"] as? String)
                let kind = limit["kind"] as? String ?? ""

                switch kind {
                case "session":
                    result.session = UsageMetric(key: "session", label: "Current Session",
                                                 percent: percent, resetAt: resetAt)
                case "weekly_all":
                    result.weeklyAll = UsageMetric(key: "weekly_all", label: "All Models",
                                                   percent: percent, resetAt: resetAt)
                case "weekly_scoped":
                    let name = scopedLabel(limit)
                    result.weeklyModels.append(
                        UsageMetric(key: "weekly_scoped:\(name)", label: name,
                                    percent: percent, resetAt: resetAt))
                default:
                    break
                }
            }
        }

        // Fallback for older API shape: if the limits array was missing, read the
        // top-level five_hour / seven_day objects instead.
        if result.session == nil, let obj = usageDict["five_hour"] as? [String: Any],
           let util = doubleValue(obj["utilization"]) {
            result.session = UsageMetric(key: "session", label: "Current Session",
                                         percent: Int(util.rounded()),
                                         resetAt: DateUtils.parseISO(obj["resets_at"] as? String))
        }
        if result.weeklyAll == nil, let obj = usageDict["seven_day"] as? [String: Any],
           let util = doubleValue(obj["utilization"]) {
            result.weeklyAll = UsageMetric(key: "weekly_all", label: "All Models",
                                           percent: Int(util.rounded()),
                                           resetAt: DateUtils.parseISO(obj["resets_at"] as? String))
        }

        // Extra pay-as-you-go usage lives under "spend" now (older API used
        // "extra_usage"). Only shown when the user has enabled it.
        if let spend = usageDict["spend"] as? [String: Any], (spend["enabled"] as? Bool) == true {
            result.extraEnabled = true
            if let used = spend["used"] as? [String: Any], let minor = doubleValue(used["amount_minor"]) {
                let exponent = doubleValue(used["exponent"]) ?? 2
                result.extraUsedCredits = minor / pow(10, exponent)
            }
            result.extraMonthlyLimit = doubleValue(spend["cap"])
        }

        // Show the per-model bars in a stable order (highest usage first).
        result.weeklyModels.sort { $0.percent > $1.percent }
    }

    // Pulls a friendly model name out of a weekly_scoped limit's `scope` object,
    // e.g. scope.model.display_name -> "Fable".
    private func scopedLabel(_ limit: [String: Any]) -> String {
        if let scope = limit["scope"] as? [String: Any] {
            if let model = scope["model"] as? [String: Any],
               let name = model["display_name"] as? String, !name.isEmpty {
                return name
            }
            if let surface = scope["surface"] as? String, !surface.isEmpty {
                return surface.capitalized
            }
        }
        return "Weekly (scoped)"
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
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
