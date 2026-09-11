import AppKit

// The menu bar icon: up to three concentric rings that fill clockwise, outermost
// first, in the same order the popover lists the limits. Which limits get a ring
// is a preference; the default is the session then the weekly cap, which is what
// the icon has always shown.
//
// Each ring is coloured INDEPENDENTLY by its own metric — orange at 60%, red at
// 80%, or red if that metric's forecast is alerting. So a fine session with a
// red weekly shows a neutral outer ring and a red inner ring, not both red.
//
// When claude.ai itself is unwell the rings stay put and a small badge appears in
// the corner. Replacing the rings with a status dot — which is what this used to
// do — threw away the number you still needed: degraded service doesn't stop you
// burning quota, and that's exactly when you want to see where you stand.
@MainActor
enum ProgressRingImage {

    // One ring's worth of input, outermost first.
    struct Ring {
        let percent: Int?
        let severity: Severity
    }

    // Geometry per ring count. Two rings reproduce the original icon exactly, so
    // nobody's menu bar shifts when this ships. Three needs a slightly larger
    // canvas and thinner outer strokes to leave the innermost room — and the
    // innermost gets a *thicker* stroke, because it has the least circumference
    // and needs the weight to stay readable at menu bar size.
    private static func geometry(_ count: Int) -> (size: CGFloat, rings: [(r: CGFloat, w: CGFloat)]) {
        switch count {
        case 0, 1: return (20, [(8.0, 2.0)])
        case 2:    return (20, [(8.0, 2.0), (4.6, 2.0)])
        default:   return (22, [(9.4, 1.3), (6.5, 1.3), (3.5, 1.7)])
        }
    }

    static func make(rings: [Ring], status: ClaudeStatus = .operational) -> NSImage {
        let shown = Array(rings.prefix(3))
        let geo = geometry(shown.count)
        let size = geo.size

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let center = CGPoint(x: size / 2, y: size / 2)

            if shown.isEmpty {
                // Nothing to report yet — draw the empty outer track so the icon
                // holds its place instead of flickering in and out.
                drawRing(ctx, center: center, radius: geo.rings[0].r,
                         lineWidth: geo.rings[0].w, percent: nil, color: .labelColor)
            } else {
                for (ring, g) in zip(shown, geo.rings) {
                    drawRing(ctx, center: center, radius: g.r, lineWidth: g.w,
                             percent: ring.percent, color: color(for: ring.severity))
                }
            }

            if !status.isHealthy { drawStatusBadge(ctx, size: size, status: status) }
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

    // A badge in the bottom-right corner.
    //
    // The gap around it is punched through to transparency rather than filled
    // with a background colour: the menu bar is whatever the wallpaper and
    // appearance make it, so any colour we picked would be wrong somewhere.
    private static func drawStatusBadge(_ ctx: CGContext, size: CGFloat, status: ClaudeStatus) {
        let d: CGFloat = 6.5

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: size - d - 2, y: -1, width: d + 2, height: d + 2))
        ctx.restoreGState()

        if case .outage = status { NSColor.systemRed.setFill() } else { NSColor.systemOrange.setFill() }
        NSBezierPath(ovalIn: NSRect(x: size - d - 1, y: 0, width: d, height: d)).fill()
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
