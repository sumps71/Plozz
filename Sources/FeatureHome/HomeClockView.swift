#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// The current time and/or date, pinned over the screen's upper right corner in
/// the same glass capsule as the top navigation bar. It sits outside the
/// scrolling content so it stays put while rows move beneath it. The app shell
/// applies it with ``SwiftUI/View/homeClockOverlay(_:)`` so it shows on every tab.
public struct HomeClockView: View {
    let mode: HomeClockMode

    public init(mode: HomeClockMode) { self.mode = mode }

    /// Matches the top bar's panel: 36pt content, 8pt item padding, 8pt inset.
    static let height: CGFloat = 68
    /// Matches the top bar's distance from the top of the screen.
    static let topMargin: CGFloat = 40

    public var body: some View {
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

extension View {
    /// Pins the clock over the screen's upper right corner, above everything in
    /// this view's hierarchy. Presented covers such as the video player sit
    /// above it, so the clock is hidden during playback.
    public func homeClockOverlay(_ mode: HomeClockMode) -> some View {
        overlay(alignment: .topTrailing) {
            if mode != .off {
                // Measured from the screen edge, not inside the safe area, which
                // on Apple TV would add roughly 60pt/90pt of its own. The view
                // fills the screen first: a fixed-size view ignoring the safe
                // area would stay where it was.
                HomeClockView(mode: mode)
                    .padding(.top, HomeClockView.topMargin)
                    .padding(.trailing, HomeClockView.topMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
            }
        }
    }
}
#endif
