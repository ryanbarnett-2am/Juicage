import SwiftUI

// The ring shown in the menu bar. It fills clockwise with usage and shifts
// color — orange at 60%, red at 80% — so the icon is a glanceable warning.
struct ProgressRingIcon: View {
    let percent: Int?
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2
    var alert: Bool = false   // a forecast says a limit will be hit — force red

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .padding(1)
    }

    private var fraction: CGFloat {
        guard let p = percent else { return 0 }
        return CGFloat(min(max(p, 0), 100)) / 100.0
    }

    private var ringColor: Color {
        if alert { return .red }
        guard let p = percent else { return .secondary }
        if p >= 80 { return .red }
        if p >= 60 { return .orange }
        return .primary
    }
}

// Renders the ring into an NSImage so the menu bar button can display it.
// (Baking SwiftUI to a bitmap is more reliable than handing arbitrary shapes
// straight to the status item.)
@MainActor
enum ProgressRingImage {
    static func make(percent: Int?, alert: Bool = false) -> NSImage {
        let renderer = ImageRenderer(content:
            ProgressRingIcon(percent: percent, size: 16, lineWidth: 2, alert: alert)
        )
        renderer.scale = 2
        if let cg = renderer.cgImage {
            return NSImage(cgImage: cg, size: NSSize(width: 18, height: 18))
        }
        return NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Claude usage")
            ?? NSImage()
    }
}
