import SwiftUI

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
        switch metric.forecast {
        case .atLimit:  return .red
        case .willHit:  return .red
        case .safe(let projected, _) where projected >= 90: return .orange
        default: break
        }
        if metric.percent >= 85 { return .red }
        if metric.percent >= 65 { return .orange }
        return .accentColor
    }

    // The pace forecast, when it has something to say. Shown *in addition to*
    // the reset line — never instead of it.
    private var forecastLine: String? {
        switch metric.forecast {
        case .atLimit:
            return "At limit"
        case .willHit(let before):
            // Behind pace: you run out this much time before the reset.
            return "On pace to hit limit ~\(DateUtils.duration(before)) early"
        case .safe(_, let spare):
            // Ahead of pace: only worth saying when the margin is meaningful.
            //
            // Right after launch the forecaster has a single sample, so it falls
            // back to "average pace since the window opened" — which at low usage
            // yields absurd headroom (e.g. "44h to spare" on a 5-hour session).
            // Requiring the spare time to fit within the time remaining keeps that
            // launch-time noise out; it resolves itself once real usage gives the
            // forecaster a measurable rate.
            if let spare, let reset = metric.resetAt {
                let timeLeft = reset.timeIntervalSinceNow
                if timeLeft > 0, spare <= timeLeft {
                    return "On pace with ~\(DateUtils.duration(spare)) to spare"
                }
            }
            return nil
        case .unknown:
            return nil
        }
    }

    // Time left / reset time — always shown when we know it.
    private var resetLine: String? {
        guard let reset = metric.resetAt else { return nil }
        switch resetStyle {
        case .countdown: return "Resets in \(DateUtils.mediumCountdown(to: reset))"
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
