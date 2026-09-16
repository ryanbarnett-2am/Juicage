import SwiftUI

// Supporting text: reset times, pace lines, captions, the footer.
//
// This was Color.secondary faded further with opacity(0.6–0.7), which measures
// 2.1–2.4:1 against white — under half the 4.5:1 accessibility minimum for small
// text, and lower again over the translucent popover. Reported as hard to read.
// Primary at 65% is 7:1 on white and still clearly quieter than headings.
extension Color {
    static let subtleText = Color.primary.opacity(0.65)
}
