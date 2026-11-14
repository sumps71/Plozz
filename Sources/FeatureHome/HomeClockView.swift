#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// The current time and/or date, pinned over Home's upper right corner in the
/// same glass capsule as the top navigation bar. It sits outside the scrolling
/// content so it stays put while rows move beneath it.
struct HomeClockView: View {
    let mode: HomeClockMode

    /// Matches the top bar's panel: 36pt content, 8pt item padding, 8pt inset.
    static let height: CGFloat = 68
    /// Matches the top bar's distance from the top of the screen.
    static let topMargin: CGFloat = 40

    var body: some View {
        // `.everyMinute` ticks on the minute boundary, so the clock never lags.
        TimelineView(.everyMinute) { context in
            // One line, so date and time together keep the bar's height.
            HStack(spacing: 16) {
                if mode.showsDate {
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                }
                if mode.showsTime {
                    Text(context.date, format: .dateTime.hour().minute())
                }
            }
            .font(.system(size: 24, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 28)
            .frame(height: Self.height)
            .plozzGlassPanel(cornerRadius: Self.height / 2, scrimOpacity: 0.08)
            .accessibilityElement(children: .combine)
        }
        .allowsHitTesting(false)
    }
}
#endif
