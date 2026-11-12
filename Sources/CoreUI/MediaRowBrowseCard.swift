#if os(tvOS)
import CoreModels
import SwiftUI

/// When a rail shows a "See all" card before its first item as well as after its
/// last, and when that leading card may take focus.
///
/// The leading card is reached only by pressing left from the first item: it
/// accepts focus while the first item (or the card itself) has it, so moving up
/// or down into a row always lands on a title rather than on "See all".
///
/// It also stays out of sight until then: the rail rests scrolled one card to
/// the right (``hiddenOffset(cardWidth:spacing:)``), which puts the first item
/// back under the row title, and returns there whenever the card loses focus —
/// so leaving the row, or moving right again, hides it.
public enum MediaRowLeadingBrowse {
    /// The rail's resting horizontal offset: exactly the leading card's slot and
    /// the gap after it, so the first item sits where it would with no card.
    public static func hiddenOffset(cardWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        max(0, cardWidth + spacing)
    }

    /// Shown wherever the trailing card is (a browse action and no loading
    /// placeholders), and only beside real items, so an empty row never shows two.
    public static func showsCard(hasBrowseAction: Bool, itemCount: Int, loadingPlaceholderCount: Int) -> Bool {
        hasBrowseAction && itemCount > 0 && loadingPlaceholderCount == 0
    }

    public static func acceptsFocus(firstItemFocused: Bool, cardFocused: Bool) -> Bool {
        firstItemFocused || cardFocused
    }
}

/// How the See all card fans its preview posters.
enum MediaRowBrowsePreview {
    static let maximumCount = 3

    struct Layout: Equatable {
        /// Horizontal offset as a multiple of the poster width.
        let offset: CGFloat
        let rotation: Double
    }

    /// The first title sits in front and centred; the next two lean out to the
    /// left and right, and lean further when the card is focused.
    /// The fan's width in poster widths at its widest (focused) spread, with a
    /// little room for the outer posters' tilt.
    static func fanWidthFactor(count: Int) -> CGFloat {
        count > 1 ? 1 + 2 * 0.62 + 0.2 : 1
    }

    static func layout(index: Int, count: Int, spread: Bool) -> Layout {
        guard count > 1, index > 0 else { return Layout(offset: 0, rotation: 0) }
        let side: CGFloat = index == 1 ? -1 : 1
        let offset = (spread ? 0.62 : 0.5) * side
        let rotation = (spread ? 11.0 : 8.0) * Double(side)
        return Layout(offset: offset, rotation: rotation)
    }
}

/// A rail action, not a media item: no playback, watch-state, or context menu.
public struct MediaRowBrowseCard: View {
    private let width: CGFloat
    private let style: PosterCardView.Style
    private let showsSeriesArtwork: Bool
    private let featuredSize: CGSize?
    private let isLeading: Bool
    private let previewItems: [MediaItem]
    private let previewArtworkPolicy: CardArtworkPolicy
    private let onFocus: () -> Void
    private let onFocusLost: () -> Void
    private let action: () -> Void
    @PlozzCardFocus private var focused: Bool
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.plozzCardStyle) private var cardStyle
    @Environment(\.plozzCardFocusStyle) private var focusStyle
    @Environment(\.plozzCardCaptionsHidden) private var captionsHidden
    @Environment(\.plozzContinueWatchingCaptionsHidden) private var continueWatchingCaptionsHidden
    @Environment(\.plozzContinueWatchingCaptionsHiddenWithArtworkTitle) private var artworkCaptionsHidden
    @Environment(\.plozzArtworkPolicy) private var artworkPolicy
    @Environment(\.plozzContinueWatchingPlaybackDetails) private var playbackDetails

    public init(
        width: CGFloat, style: PosterCardView.Style = .poster, showsSeriesArtwork: Bool = false,
        featuredSize: CGSize? = nil, isLeading: Bool = false,
        previewItems: [MediaItem] = [], previewArtworkPolicy: CardArtworkPolicy = .standard,
        onFocus: @escaping () -> Void = {},
        onFocusLost: @escaping () -> Void = {}, action: @escaping () -> Void
    ) {
        self.isLeading = isLeading
        self.previewItems = Array(previewItems.prefix(MediaRowBrowsePreview.maximumCount))
        self.previewArtworkPolicy = previewArtworkPolicy
        self.width = width
        self.style = style
        self.showsSeriesArtwork = showsSeriesArtwork
        self.featuredSize = featuredSize
        self.onFocus = onFocus
        self.onFocusLost = onFocusLost
        self.action = action
    }

    private var aspectRatio: CGFloat {
        if let featuredSize { return featuredSize.width / featuredSize.height }
        if style == .poster { return showsSeriesArtwork ? playbackDetails.cardAspectRatio : 2 / 3 }
        return showsSeriesArtwork ? ContinueWatchingCardShape.aspectRatio : 16 / 9
    }

    private var showsCaption: Bool {
        if featuredSize != nil { return false }
        if showsSeriesArtwork || artworkPolicy.area == .continueWatching {
            return !(showsSeriesArtwork ? artworkCaptionsHidden : continueWatchingCaptionsHidden)
        }
        return !captionsHidden
    }

    private var radius: CGFloat {
        if featuredSize != nil { return 20 }
        return style == .poster ? metrics.posterArtworkCornerRadius : metrics.landscapeArtworkCornerRadius
    }

    public var body: some View {
        control
            .frame(width: width)
            .accessibilityLabel(Text("See all"))
            .accessibilityIdentifier(isLeading ? "home-row-see-all-leading" : "home-row-see-all")
            .onChange(of: focused) { _, value in if value { onFocus() } else { onFocusLost() } }
    }

    @ViewBuilder
    private var control: some View {
        if let featuredSize {
            if focusStyle.usesSystemEffect {
                NativeTVPoster(
                    image: nil, treatment: .original, aspectRatio: aspectRatio, fallbackWidth: width,
                    title: .localized("See all"), subtitle: nil, overlay: label,
                    focus: $focused, action: action
                )
                .frame(width: featuredSize.width, height: featuredSize.height)
            } else {
                artwork.frame(width: featuredSize.width, height: featuredSize.height)
                    .plozzFocusHalo(cornerRadius: radius, focusScale: 1.04, isFocused: focused)
                    .focusableCard(isFocused: $focused, cornerRadius: radius, action: action)
                    .plozzCardFocusTransition(isFocused: focused)
            }
        } else if cardStyle == .borderless, focusStyle.usesSystemEffect {
            let artworkWidth = width - 2 * metrics.borderlessCardSideMargin
            VStack(spacing: metrics.nativePosterCaptionSpacing) {
                NativeTVPoster(
                    image: nil, treatment: .original, aspectRatio: aspectRatio, fallbackWidth: artworkWidth,
                    title: .localized("See all"), subtitle: nil, overlay: label, focus: $focused, action: action
                )
                .frame(width: artworkWidth)
                if showsCaption {
                    SystemPosterCaption(
                        title: .localized("See all"), subtitle: nil, reservesSubtitleSpace: true, isFocused: focused
                    )
                    .frame(width: artworkWidth)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.borderlessCardSideMargin)
        } else {
            styledCard
                .focusableCard(isFocused: $focused, cornerRadius: radius, action: action)
                .plozzCardFocusTransition(isFocused: focused)
        }
    }

    @ViewBuilder
    private var styledCard: some View {
        if cardStyle == .framed {
            VStack(spacing: style == .poster ? metrics.posterCaptionTopSpacing : metrics.landscapeCaptionTopSpacing) {
                artwork.aspectRatio(aspectRatio, contentMode: .fit)
                if showsCaption {
                    caption.padding(.bottom, style == .poster ? metrics.posterCaptionInset : metrics.landscapeCaptionInset)
                }
            }
            .plozzFramedMediaCard(innerCornerRadius: radius, isFocused: focused && focusStyle.drawsFocusOutline)
            .plozzRestingCardShadow(isFocused: focused)
            .plozzCardFocusLift(
                isFocused: focused, cornerRadius: radius + metrics.cardInset,
                outlineScale: style == .poster ? PlozzTheme.Metrics.focusedCardScale : PlozzTheme.Metrics.mediumFocusedCardScale
            )
        } else {
            VStack(spacing: metrics.posterCaptionTopSpacing + metrics.focusCaptionPush(for: focusStyle)) {
                artwork.aspectRatio(aspectRatio, contentMode: .fit)
                    .plozzFocusHalo(
                        cornerRadius: radius, focusScale: PlozzTheme.Metrics.mediumFocusedCardScale, isFocused: focused
                    )
                if showsCaption {
                    caption.offset(y: focused ? 0 : -metrics.focusCaptionPush(for: focusStyle))
                }
            }
            .padding(.horizontal, metrics.borderlessCardSideMargin)
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(palette.fill)
            .overlay { label }
    }

    /// The card's face: a fanned stack of the row's first posters with an arrow
    /// badge, or the badge alone when the row has no artwork to preview. Tall
    /// cards stack the badge under the fan; wide cards put it beside the fan so
    /// neither covers the other.
    private var label: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isWide = size.width > size.height * 1.1
            Group {
                if previewItems.isEmpty {
                    badge.frame(width: size.width, height: size.height)
                } else if isWide {
                    HStack(spacing: 0) {
                        posterFan(height: size.height * 0.72, maxWidth: size.width * 0.48)
                            .frame(width: size.width * 0.58, height: size.height)
                        badge.frame(width: size.width * 0.42, height: size.height)
                    }
                } else {
                    ZStack(alignment: .bottom) {
                        posterFan(height: size.height * 0.5, maxWidth: size.width * 0.92)
                            .frame(width: size.width, height: size.height)
                            .offset(y: -size.height * 0.1)
                        // Lets the badge and its text read over any artwork.
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                        badge.padding(.bottom, size.height * 0.07)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private var badge: some View {
        VStack(spacing: 10 * metrics.scale) {
            Image(systemName: "arrow.right")
                .font(.system(size: 26 * metrics.scale, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 64 * metrics.scale, height: 64 * metrics.scale)
                .background(Circle().fill(.white.opacity(focused ? 1 : 0.9)))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .scaleEffect(focused ? 1.08 : 1)
            if !showsCaption {
                Text("See all")
                    .font(.headline)
                    .foregroundStyle(previewItems.isEmpty ? palette.primaryText : .white)
                    .shadow(color: .black.opacity(previewItems.isEmpty ? 0 : 0.4), radius: 6, y: 2)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: focused)
    }

    /// Up to three posters fanned around the centre, the first title in front,
    /// sized so the whole fan fits `maxWidth`. Posters only: an episode resolves
    /// to its show's poster, never its own frame, so the preview can't spoil
    /// anything.
    private func posterFan(height: CGFloat, maxWidth: CGFloat) -> some View {
        let spread = focused && !reduceMotion
        let widthFactor = MediaRowBrowsePreview.fanWidthFactor(count: previewItems.count)
        let posterWidth = min(height * 2 / 3, maxWidth / widthFactor)
        let posterHeight = posterWidth * 3 / 2
        return ZStack {
            ForEach(Array(previewItems.enumerated()).reversed(), id: \.element.stablePresentationID) { index, item in
                let layout = MediaRowBrowsePreview.layout(index: index, count: previewItems.count, spread: spread)
                FallbackAsyncImage(
                    references: previewArtworkPolicy.references(for: item, style: .poster),
                    variant: .posterCard
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    palette.fill.brightness(0.08)
                }
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8 * metrics.scale, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                .rotationEffect(.degrees(layout.rotation))
                .offset(x: layout.offset * posterWidth, y: abs(layout.offset) * posterHeight * 0.08)
                .brightness(index == 0 ? 0 : -0.12)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: spread)
    }

    private var caption: some View {
        VStack(spacing: style == .poster ? 2 : 4) {
            Text("See all").font(.subheadline.weight(.semibold))
            Text(verbatim: " ").font(.system(size: 20 * metrics.scale)).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
