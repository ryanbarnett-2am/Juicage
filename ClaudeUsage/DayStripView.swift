import SwiftUI

// Today, as a timeline of session windows.
//
// A session window is five rolling hours anchored to whenever it opened, so —
// unlike the weekly cap — its boundaries are yours to aim. That's invisible in a
// percentage. Against a clock it's obvious: a window that opened while you
// weren't working, quietly burning down, and the hours where none was open.
//
// The axis is the calendar day rather than a rolling window, because the
// question is "how should I use the rest of today", which needs the hours ahead
// on screen as much as the ones behind.
struct DayStripView: View {
    let windows: [UsageWindow]
    let windowLength: TimeInterval

    private var dayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var dayEnd: Date { dayStart.addingTimeInterval(24 * 3600) }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        let span = dayEnd.timeIntervalSince(dayStart)
        let fraction = date.timeIntervalSince(dayStart) / span
        return CGFloat(min(max(fraction, 0), 1)) * width
    }

    private func hourLabel(_ hour: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "ha"
        return f.string(from: dayStart.addingTimeInterval(Double(hour) * 3600))
            .replacingOccurrences(of: "AM", with: "a")
            .replacingOccurrences(of: "PM", with: "p")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today's sessions")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DateUtils.clockTime(Date()))
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.10))

                    // Quarter-day ticks, so a block's position reads as a time
                    // rather than just a place on a bar.
                    ForEach([6, 12, 18], id: \.self) { hour in
                        Path { p in
                            let x = position(dayStart.addingTimeInterval(Double(hour) * 3600), width: w)
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    }

                    ForEach(windows) { window in
                        let opened = window.resetAt.addingTimeInterval(-windowLength)
                        let x0 = position(opened, width: w)
                        let bw = max(2, position(window.resetAt, width: w) - x0)
                        let frac = CGFloat(min(max(window.peakPercent, 0), 100)) / 100
                        let live = window.resetAt > Date()

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: bw, height: h)
                            // Height is how full it got, so unused capacity shows
                            // as the empty space above.
                            RoundedRectangle(cornerRadius: 2)
                                .fill(window.peakPercent >= 100 ? Color.red
                                      : Color.accentColor.opacity(live ? 0.85 : 0.5))
                                .frame(width: bw, height: max(2, frac * h))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(live ? Color.accentColor.opacity(0.8) : .clear,
                                              lineWidth: 1)
                                .frame(width: bw, height: h)
                        )
                        .offset(x: x0)
                    }

                    // Now — sits where it actually is, so the space to its right
                    // is the day you have left.
                    Path { p in
                        let x = position(Date(), width: w)
                        p.move(to: CGPoint(x: x, y: -2))
                        p.addLine(to: CGPoint(x: x, y: h + 2))
                    }
                    .stroke(Color.primary.opacity(0.55), lineWidth: 1.5)
                }
            }
            .frame(height: 30)

            HStack(spacing: 0) {
                Text(hourLabel(0)); Spacer()
                Text(hourLabel(6)); Spacer()
                Text(hourLabel(12)); Spacer()
                Text(hourLabel(18)); Spacer()
                Text(hourLabel(24))
            }
            .font(.caption2)
            .foregroundStyle(Color.secondary.opacity(0.6))
        }
    }
}
