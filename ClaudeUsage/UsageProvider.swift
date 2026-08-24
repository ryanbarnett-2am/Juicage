import Foundation

// One source of usage data.
//
// This is the seam along which other services get added — ChatGPT, Copilot,
// Cursor and friends all sell the same shape of thing: a quota that burns down
// and resets on a schedule. Everything downstream already speaks `UsageMetric`
// (label, percent, resets-at), which describes any of them, so a new provider is
// a fetch and a parse rather than a new app.
//
// Providers are deliberately push-based rather than async/await: claude.ai's
// numbers arrive whenever a parked web view finishes a round trip, not when a
// caller asks, and a provider may deliver several times per fetch.
protocol UsageProvider: AnyObject {
    var id: String { get }            // stable key, e.g. "claude"
    var displayName: String { get }   // shown once more than one is enabled

    // Every account/workspace this provider knows about. Delivered on the main
    // queue, tagged with the provider that produced it.
    var onUsage: (([WorkspaceUsage]) -> Void)? { get set }
    var onNeedsLogin: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }

    func start()   // long-lived setup: parked web view, session timers, …
    func fetch()   // pull fresh numbers now
}

// MARK: - Claude

// claude.ai, via the hidden web view in UsageFetcher. All the Claude-specific
// knowledge stays in UsageFetcher and UsageParser; this is only the adapter that
// makes it look like any other provider.
final class ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"

    var onUsage: (([WorkspaceUsage]) -> Void)?
    var onNeedsLogin: (() -> Void)?
    var onError: ((String) -> Void)?

    private var fetcher: UsageFetcher?

    func start() {
        guard fetcher == nil else { return }
        let fetcher = UsageFetcher()

        fetcher.onWorkspacesReceived = { [weak self] list in
            guard let self else { return }
            // Stamp each workspace with its source so the UI can group by
            // provider and so identifiers can't collide across providers.
            let tagged = list.map { workspace -> WorkspaceUsage in
                var copy = workspace
                copy.providerID = self.id
                copy.providerName = self.displayName
                return copy
            }
            DispatchQueue.main.async { self.onUsage?(tagged) }
        }
        fetcher.onNeedsLogin = { [weak self] in
            DispatchQueue.main.async { self?.onNeedsLogin?() }
        }
        fetcher.onError = { [weak self] message in
            DispatchQueue.main.async { self?.onError?(message) }
        }

        self.fetcher = fetcher
    }

    // The fetcher kicks off its own first fetch once the parked page loads, so
    // this is only the periodic refresh.
    func fetch() {
        fetcher?.fetch()
    }
}
