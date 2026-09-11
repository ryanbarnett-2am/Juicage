import SwiftUI
import WebKit

struct LoginView: View {
    // The account's cookie jar. Signing in against the shared store would just
    // replace whichever account was already there.
    var dataStore: WKWebsiteDataStore = .default()
    let onLoggedIn: () -> Void
    @State private var showContinue = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.blue)
                Text("Sign in to Claude.ai")
                    .fontWeight(.medium)
                Spacer()
                if showContinue {
                    Button("Continue →") {
                        onLoggedIn()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            LoginWebView(dataStore: dataStore, onLoggedIn: onLoggedIn, onShowContinue: {
                showContinue = true
            })
        }
    }
}

struct LoginWebView: NSViewRepresentable {
    var dataStore: WKWebsiteDataStore = .default()
    let onLoggedIn: () -> Void
    let onShowContinue: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoggedIn: onLoggedIn, onShowContinue: onShowContinue)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onLoggedIn: () -> Void
        let onShowContinue: () -> Void
        private var didTrigger = false

        init(onLoggedIn: @escaping () -> Void, onShowContinue: @escaping () -> Void) {
            self.onLoggedIn = onLoggedIn
            self.onShowContinue = onShowContinue
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            let urlString = url.absoluteString

            let onClaude = url.host?.hasSuffix("claude.ai") == true
            let isAuthFlow = urlString.contains("/login")
                          || urlString.contains("/oauth")
                          || urlString.contains("accounts.google")
                          || urlString.contains("appleid.apple")

            // Auto-detect login success
            if onClaude && !isAuthFlow && !didTrigger {
                didTrigger = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.onLoggedIn()
                }
                return
            }

            // If we're on a claude.ai page at all (even mid-auth), show the manual button
            if onClaude && !urlString.contains("/login") {
                DispatchQueue.main.async {
                    self.onShowContinue()
                }
            }
        }
    }
}
