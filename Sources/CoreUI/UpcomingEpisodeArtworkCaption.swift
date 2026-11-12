#if canImport(SwiftUI)
import SwiftUI
import CoreModels

/// The Upcoming Episodes caption ("S2, E5 · In 3 days") drawn on the artwork, where
/// a Continue Watching card draws its resume chip (``ResumeChipOverlay``): the same
/// type, colour, inset and bottom scrim, but no play glyph, runtime or progress,
/// because an unaired episode has none of those.
///
/// The card's accessibility value already carries the caption, so this is hidden
/// from assistive technologies to avoid reading it twice.
struct UpcomingEpisodeArtworkCaption: View {
    private let text: String
    private let compactHorizontalLayout: Bool
    private var rendersScrim = true
    private var playbackTextSize: CGFloat?
    private var playbackInset: CGFloat?

    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzChromeIsFocused) private var isFocused

    init(text: String, compactHorizontalLayout: Bool = false) {
        self.text = text
        self.compactHorizontalLayout = compactHorizontalLayout
    }

    func fittingPlaybackText(size: CGFloat?, inset: CGFloat?) -> Self {
        var result = self
        result.playbackTextSize = size
        result.playbackInset = inset
        return result
    }

    var withoutScrim: Self {
        var result = self
        result.rendersScrim = false
        return result
    }

    /// The same bottom ramp a series-artwork Continue Watching card uses.
    var artworkScrim: MediaArtworkChromeScrim {
        MediaArtworkChromeScrim(
            top: false, bottom: true,
            bottomStart: ContinueWatchingCardShape.scrimStart,
            bottomDepth: ContinueWatchingCardShape.scrimDepth
        )
    }

    var body: some View {
        Color.clear
            .overlay { if rendersScrim { artworkScrim } }
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    let contentInset = playbackInset ?? metrics.resumeChipInset
                    let inset = compactHorizontalLayout
                        ? min(contentInset, geometry.size.width * 0.05) : contentInset
                    Text(verbatim: text)  // l10n:content — preformatted numbering and air timing
                        .font(.system(size: playbackTextSize ?? metrics.resumeChipFontSize, weight: .semibold))
                        .foregroundStyle(PlozzMediaChrome.foreground(isFocused: isFocused))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(inset)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
