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
            infoState(icon: "person.crop.circle.badge.exclamationmark",
                      text: "Sign in to see your usage")

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
                ExtraUsageRow(used: workspace.extraUsedCredits, limit: workspace.extraMonthlyLimit)
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

    private var subtitle: String? {
        switch metric.forecast {
        case .atLimit:
            return "At limit"
        case .willHit(let before):
            // Behind pace: you run out this much time before the reset.
            return "On pace to hit limit ~\(DateUtils.duration(before)) early"
        case .safe(_, let spare):
            // Ahead of pace: show the time margin, unless it's huge (comfortably
            // safe) or unknown (idle) — then just show the reset time.
            if let spare, spare <= 48 * 3600 {
                return "On pace with ~\(DateUtils.duration(spare)) to spare"
            }
        case .unknown:
            break
        }
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

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(metric.forecast.isAlerting ? barColor : Color.secondary.opacity(0.7))
            }
        }
    }
}

// MARK: - Extra (pay-as-you-go) credits

struct ExtraUsageRow: View {
    let used: Double?
    let limit: Double?

    var body: some View {
        HStack {
            Text("Extra usage").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let used {
                let limitStr = limit.map { " / \(Int($0))" } ?? ""
                Text("\(Int(used))\(limitStr) credits")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
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
