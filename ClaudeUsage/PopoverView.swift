import SwiftUI
import Combine   // Timer.publish, for the ticking elapsed time on local jobs

struct PopoverView: View {
    @EnvironmentObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("Tally").font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button { viewModel.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if !viewModel.claudeStatus.isHealthy {
                StatusBannerView(status: viewModel.claudeStatus)
            }

            Divider()

            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            // Only appears while something is actually running — an idle section
            // would just be clutter in a popover you open to check a number.
            if viewModel.isLocalBusy {
                Divider()
                LocalJobsSection(jobs: viewModel.localJobs,
                                 completed: viewModel.localCompleted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            Divider()

            // Footer
            HStack(spacing: 4) {
                if viewModel.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(viewModel.isStale ? Color.orange : Color.secondary.opacity(0.6))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    private var footerText: String {
        if viewModel.lastUpdated == nil { return "Not yet loaded" }
        if viewModel.isStale { return "Stale — updated \(viewModel.lastUpdatedText)" }
        return "Updated \(viewModel.lastUpdatedText)"
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.needsLogin {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Sign in to see your usage")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sign In") {
                    NotificationCenter.default.post(name: .openLogin, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

        } else if viewModel.workspaces.isEmpty, let err = viewModel.errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Couldn't load usage").font(.callout).foregroundStyle(.secondary)
                Text(err).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

        } else if viewModel.workspaces.isEmpty {
            infoState(icon: "hourglass", text: "Loading your usage…")

        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(viewModel.workspaces.enumerated()), id: \.element.id) { index, ws in
                    if index > 0 { Divider() }
                    WorkspaceSection(workspace: ws,
                                     showName: viewModel.workspaces.count > 1)
                }
            }
        }
    }

    private func infoState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - One workspace's block of bars

struct WorkspaceSection: View {
    let workspace: WorkspaceUsage
    let showName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showName, let name = workspace.workspaceName {
                Text(name)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if let session = workspace.session {
                UsageRowView(metric: session, resetStyle: .countdown)
            }
            if let weekly = workspace.weeklyAll {
                UsageRowView(metric: weekly, resetStyle: .date)
            }
            // Per-model weekly caps — Fable and friends appear here automatically.
            ForEach(workspace.weeklyModels) { model in
                UsageRowView(metric: model, resetStyle: .date)
            }

            if workspace.extraEnabled {
                ExtraUsageRow(used: workspace.extraUsedCredits,
                              limit: workspace.extraMonthlyLimit,
                              currency: workspace.extraCurrency)
            }

            if let error = workspace.error {
                Text("⚠ \(error)")
                    .font(.caption2).foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - One usage bar

struct UsageRowView: View {
    enum ResetStyle { case countdown, date }

    let metric: UsageMetric
    let resetStyle: ResetStyle

    private var barColor: Color {
        switch severity(percent: metric.percent, forecast: metric.forecast) {
        case .ok:     return .accentColor
        case .warn:   return .orange
        case .danger: return .red
        }
    }

    // The pace forecast, when it has something to say. Shown *in addition to*
    // the reset line — never instead of it.
    private var forecastLine: String? {
        switch metric.forecast {
        case .atLimit:
            return "At limit"
        case .willHit(_, let runsOut):
            // The question people actually have is "how long do I have?", not
            // "how far ahead of the reset will I run dry?". Phrasing it against
            // the reset made the reset sound like the deadline, when the tokens
            // run out first.
            //
            // Clock time leads because that's what you plan against; the
            // duration follows for anyone who reads it the other way.
            let at = DateUtils.clockTime(Date().addingTimeInterval(runsOut))
            return "At this pace you'll run out around \(at) (\(DateUtils.duration(runsOut)))"
        case .safe(let projected, let spare, _):
            // Report where you're heading, not how much slack is left.
            //
            // This used to show "~Nh to spare" and hide itself whenever that
            // figure exceeded the time remaining — a guard against the OLD
            // sample-based forecaster, which could claim "44h to spare" on a
            // 5-hour session. The forecaster is stateless average pace now and
            // can't produce that, so the guard only suppressed good output: past
            // the midpoint of a window it blanked the line entirely unless usage
            // was already high, which is exactly when you want the reassurance.
            //
            // Projected percentage is also just more useful — "about 45% by
            // reset" says where you land; hours-of-slack doesn't.
            if let spare, let reset = metric.resetAt {
                let timeLeft = reset.timeIntervalSinceNow
                if timeLeft > 0, spare <= timeLeft {
                    return "On pace — about \(projected)% by reset · ~\(DateUtils.duration(spare)) to spare"
                }
            }
            return "On pace — about \(projected)% by reset"
        case .warmingUp:
            // Pace looks steep but too little used to trust — tell the user we're
            // watching without crying wolf.
            return "Calculating pace…"
        case .unknown:
            return nil
        }
    }

    // Time left / reset time — always shown when we know it.
    private var resetLine: String? {
        guard let reset = metric.resetAt else { return nil }
        switch resetStyle {
        case .countdown: return "Resets at \(DateUtils.clockTime(reset)) (\(DateUtils.mediumCountdown(to: reset)))"
        case .date:      return "Resets \(DateUtils.resetDate(reset))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label).font(.callout).fontWeight(.medium)
                Spacer()
                Text("\(metric.percent)%")
                    .font(.callout).fontWeight(.semibold)
                    .foregroundStyle(barColor)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: max(6, geo.size.width * CGFloat(metric.percent) / 100))
                        .animation(.easeInOut(duration: 0.4), value: metric.percent)
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            if let forecastLine {
                Text(forecastLine)
                    .font(.caption2)
                    .foregroundStyle(metric.forecast.isAlerting ? barColor : Color.secondary.opacity(0.7))
            }
            if let resetLine {
                Text(resetLine)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
    }
}

// MARK: - Local models at work

// One row per local model currently generating. The elapsed time has to tick on
// its own — nothing else in the popover changes between the 3-minute fetches.
struct LocalJobsSection: View {
    let jobs: [LocalJob]
    let completed: Int          // finished so far in this burst
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(jobs.count > 1 ? "\(jobs.count) local models working" : "Local model working")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                // A batch fires many short jobs in a row; without a tally it looks
                // like one job stuck at a few seconds.
                if completed > 0 {
                    Text("· \(completed) done")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            ForEach(jobs) { job in
                LocalJobRow(job: job, now: now)
            }
        }
        .onReceive(ticker) { now = $0 }
    }
}

struct LocalJobRow: View {
    let job: LocalJob
    let now: Date

    // Recomputed against the ticking `now` rather than reading job.elapsed, so
    // SwiftUI actually re-renders each second.
    private var detail: String {
        var parts: [String] = []
        if job.isPreparing { parts.append("reading prompt") }
        if let rate = job.tokensPerSec, rate > 0 { parts.append("\(Int(rate.rounded())) tok/s") }
        parts.append(DateUtils.compactElapsed(now.timeIntervalSince(job.startedAt)))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.model)
                        .font(.callout).fontWeight(.medium)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(job.engine.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Ollama never logs prompt text, so this is LM Studio only.
                if Preferences.shared.showLocalTitles, let title = job.title {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(detail)
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
    }
}

// MARK: - Extra (pay-as-you-go) credits

struct ExtraUsageRow: View {
    let used: Double?
    let limit: Double?
    let currency: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Extra usage").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let used {
                Text(summary(used))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    // "$0.12 of $5.00 · $4.88 left" — or just the spend if there's no cap.
    private func summary(_ used: Double) -> String {
        guard let limit, limit > 0 else { return money(used) }
        let left = max(0, limit - used)
        return "\(money(used)) of \(money(limit)) · \(money(left)) left"
    }

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency ?? "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Status banner

struct StatusBannerView: View {
    let status: ClaudeStatus

    private var color: Color {
        if case .outage = status { return .red } else { return .orange }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(status.description).font(.caption).fontWeight(.medium)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }
}
