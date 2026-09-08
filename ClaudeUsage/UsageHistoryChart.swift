import SwiftUI

// Recent windows as bars — one bar per closed window, height = the peak reached
// inside it.
//
// Bars rather than a line because these are discrete periods, not a continuous
// series: a line drawn between them would imply usage travelled from one week's
// 74% to the next week's 100%, when they're unrelated. Bars also let a window
// that hit the cap be coloured differently, so "how often did I run out" is
// countable rather than merely asserted by the caption.
struct UsageHistoryChart: View {
    let values: [Int]           // percentages, oldest first
    var color: Color = .secondary

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let slot = geo.size.width / CGFloat(max(values.count, 1))
            let barW = max(2, slot - 2)

            ZStack(alignment: .topLeading) {
                // The ceiling. Without it a short bar reads as "small" rather
                // than "small out of everything I could have used".
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                }
                .stroke(Color.secondary.opacity(0.25),
                        style: .init(lineWidth: 1, dash: [2, 2]))

                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let frac = CGFloat(min(max(value, 0), 100)) / 100
                    let barH = max(1.5, frac * h)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: barW, height: h)
                        RoundedRectangle(cornerRadius: 1)
                            // A window that ran out is always red, whatever the
                            // metric's current colour — that's the fact you're
                            // scanning for.
                            .fill(value >= 100 ? Color.red : color.opacity(0.85))
                            .frame(width: barW, height: barH)
                    }
                    .frame(width: slot, alignment: .leading)
                    .offset(x: CGFloat(index) * slot)
                }
            }
        }
    }
}
