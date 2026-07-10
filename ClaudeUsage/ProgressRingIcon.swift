import AppKit

// The menu bar icon: two concentric rings that fill clockwise.
//   • Outer ring = current session usage
//   • Inner ring = weekly (all models) usage
// Each ring shifts color independently — orange at 60%, red at 80% — so a glance
// tells you which limit is getting tight. `alert` forces both red (a forecast
// says a limit will be hit).
@MainActor
enum ProgressRingImage {

    static func make(session: Int?, weekly: Int?, alert: Bool = false) -> NSImage {
        let size: CGFloat = 20
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let center = CGPoint(x: size / 2, y: size / 2)
            let lineWidth: CGFloat = 2.0

            drawRing(ctx, center: center, radius: 8.0, lineWidth: lineWidth,
                     percent: session, color: ringColor(session, alert: alert))   // outer = session
            drawRing(ctx, center: center, radius: 4.6, lineWidth: lineWidth,
                     percent: weekly, color: ringColor(weekly, alert: alert))      // inner = weekly
            return true
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

    private static func ringColor(_ percent: Int?, alert: Bool) -> NSColor {
        if alert { return .systemRed }
        guard let p = percent else { return .secondaryLabelColor }
        if p >= 80 { return .systemRed }
        if p >= 60 { return .systemOrange }
        return .labelColor
    }
}
