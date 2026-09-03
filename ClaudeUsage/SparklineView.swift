import SwiftUI

// A small history line under a usage bar: one point per completed window, oldest
// on the left.
//
// Deliberately unlabelled and unscaled — at this size axes and gridlines cost
// more than they explain. It answers "is this normal for me?" at a glance, and
// the popover carries the exact numbers for anything more precise.
struct SparklineView: View {
    let values: [Int]           // percentages, oldest first
    var color: Color = .secondary

    // Always scaled 0-100 rather than to the data's own range. A run of 3%, 5%
    // and 4% weeks would otherwise draw the same dramatic peaks as 30%, 90% and
    // 60%, which is exactly the wrong impression.
    private let maxValue: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let points = positions(in: CGSize(width: w, height: h))

            ZStack(alignment: .bottomLeading) {
                // A faint 100% marker, so a line sitting near the top reads as
                // "close to the cap" rather than merely "high for this chart".
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addLine(to: CGPoint(x: w, y: 1))
                }
                .stroke(Color.secondary.opacity(0.18), style: .init(lineWidth: 1, dash: [2, 2]))

                if points.count >= 2 {
                    Path { p in
                        p.move(to: points[0])
                        for pt in points.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color.opacity(0.75),
                            style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // Mark the most recent window so the eye lands on "where I ended
                // up last time" rather than on the tallest point.
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 3.5, height: 3.5)
                        .position(x: last.x, y: last.y)
                }
            }
        }
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(CGFloat(value), 0), maxValue)
            // Inset by a point top and bottom so a 0% or 100% run isn't clipped
            // flat against the edge.
            let usable = size.height - 2
            return CGPoint(x: CGFloat(index) * stepX,
                           y: 1 + usable - (clamped / maxValue) * usable)
        }
    }
}
