import AppKit

// The menu bar icon: two concentric rings that fill clockwise.
//   • Outer ring = current session usage
//   • Inner ring = weekly (all models) usage
// Each ring is colored INDEPENDENTLY by its own metric — orange at 60%, red at
// 80%, or red if that metric's forecast is alerting. So a fine session with a
// red weekly shows a neutral outer ring and a red inner ring, not both red.
@MainActor
enum ProgressRingImage {

    static func make(session: Int?, sessionSeverity: Severity,
                     weekly: Int?, weeklySeverity: Severity) -> NSImage {
        let size: CGFloat = 20
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let center = CGPoint(x: size / 2, y: size / 2)
            let lineWidth: CGFloat = 2.0

            drawRing(ctx, center: center, radius: 8.0, lineWidth: lineWidth,
                     percent: session, color: color(for: sessionSeverity))   // outer = session
            drawRing(ctx, center: center, radius: 4.6, lineWidth: lineWidth,
                     percent: weekly, color: color(for: weeklySeverity))      // inner = weekly
            return true
        }
    }

    private static func color(for s: Severity) -> NSColor {
        switch s {
        case .ok:     return .labelColor      // neutral (adapts to the menu bar)
        case .warn:   return .systemOrange
        case .danger: return .systemRed
        }
    }

    private static func drawRing(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                 lineWidth: CGFloat, percent: Int?, color: NSColor) {
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // Track
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Progress arc — starts at top, sweeps clockwise.
        guard let p = percent, p > 0 else { return }
        let fraction = CGFloat(min(max(p, 0), 100)) / 100.0
        color.setStroke()
        let start = CGFloat.pi / 2
        let end = start - fraction * .pi * 2
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        ctx.strokePath()
    }

}
