#if os(tvOS)
import CoreModels
import CoreUI
import SwiftUI

/// The information panel beside the "See all" grid when Settings > Appearance >
/// See all layout is Grid with details: the focused title's backdrop, name,
/// details, ratings, synopsis and credits. Information only — it never takes
/// focus, so the grid behaves exactly as it does without it.
///
/// Grid with pop-up details shows the same information in ``Style/popup``: a
/// floating card beside the title focus has rested on.
struct HomeRowBrowseDetailPanel: View {
    enum Style {
        /// Full height at the screen's trailing edge.
        case panel
        /// A floating card sized to its content.
        case popup
    }

    static let width: CGFloat = 580
    static let popupWidth: CGFloat = 640
    static let popupCornerRadius: CGFloat = 28
    /// Clear space between the grid and the panel, so a focused card in the
    /// grid's last column can grow and lift without running under the panel.
    static let gridGap: CGFloat = 40

    /// How many of the grid's `columns` remain beside the panel. Poster walls
    /// lose two so the cards grow; a landscape grid is already narrow and loses
    /// one, never going below a single column.
    static func columnCount(beside columns: Int) -> Int {
        max(1, columns - (columns > 4 ? 2 : 1))
    }

    let item: MediaItem?
    let spoilerSettings: SpoilerSettings
    /// The drawn width, which can exceed ``width`` to reach the screen's edge
    /// past the safe area the panel's layout slot ends at.
    var drawnWidth: CGFloat = Self.width
    var style: Style = .panel
    @Environment(\.themePalette) private var palette

    var body: some View {
        switch style {
        case .panel: panel
        case .popup: popup
        }
    }

    private var popup: some View {
        Group {
            if let item {
                content(for: item)
                    .padding(.bottom, 40)
            }
        }
        .frame(width: drawnWidth, alignment: .topLeading)
        .background(palette.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Self.popupCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 36, y: 18)
        .focusable(false)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var panel: some View {
        ZStack(alignment: .topLeading) {
            palette.backgroundSecondary
            if let item {
                content(for: item)
                    .id(item.stablePresentationID)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: item?.stablePresentationID)
        .focusable(false)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(for item: MediaItem) -> some View {
        let hidesText = spoilerSettings.shouldHideText(for: item)
        VStack(alignment: .leading, spacing: 0) {
            backdrop(for: item)
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: title(for: item)) // l10n:content — media title from the server
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, -36)
                if let subtitle = episodeLine(for: item, hidesText: hidesText) {
                    Text(verbatim: subtitle) // l10n:content — episode numbering and server title
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                }
                if let details = detailsLine(for: item) {
                    Text(verbatim: details) // l10n:content — server metadata joined with dots
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                }
                let ratings = DetailPageSettings.default.headerRatings(
                    from: item.ratings, isAnime: false, hidesRatings: hidesText
                )
                if !ratings.isEmpty {
                    RatingsBadgeRow(ratings: ratings)
                }
                if !hidesText, let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !overview.isEmpty {
                    Text(verbatim: overview) // l10n:content — synopsis from the server
                        .font(.system(size: 25))
                        .foregroundStyle(palette.secondaryText)
                        .lineSpacing(4)
                        .lineLimit(style == .popup ? 5 : 9)
                        .padding(.top, 6)
                }
                credits(for: item)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 48)
        }
    }

    /// Episodes show their show's art, never their own frame, so the panel
    /// can't spoil what happens in them.
    private func backdrop(for item: MediaItem) -> some View {
        let references = item.kind == .episode
            ? item.seriesArtworkReferences()
            : [item.backdropURL, item.fallbackArtworkURL].compactMap { $0 }.map(ArtworkReference.remote)
        return FallbackAsyncImage(references: references, variant: .landscapeCard) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            palette.fill
        }
        .frame(width: drawnWidth, height: drawnWidth * (style == .popup ? 1 / 2 : 9 / 16))
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, palette.backgroundSecondary],
                startPoint: .center, endPoint: .bottom
            )
        }
    }

    private func title(for item: MediaItem) -> String {
        if item.kind == .episode, let show = item.parentTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !show.isEmpty {
            return show
        }
        return item.title
    }

    private func episodeLine(for item: MediaItem, hidesText: Bool) -> String? {
        guard item.kind == .episode else { return nil }
        let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [item.seasonEpisodeLabel, hidesText || name.isEmpty ? nil : name].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func detailsLine(for item: MediaItem) -> String? {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        parts += item.genres.prefix(2)
        if let runtime = item.runtime, runtime > 0 {
            if let text = runtime.runtimeBadgeText { parts.append(text) } // the same "1h 36m" the posters show
        }
        if let rating = item.officialRating?.trimmingCharacters(in: .whitespacesAndNewlines), !rating.isEmpty {
            parts.append(rating)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func credits(for item: MediaItem) -> some View {
        let directors = item.people.filter { $0.kind?.lowercased() == "director" }.map(\.name).prefix(2)
        let cast = item.cast.map(\.name).prefix(3)
        if !directors.isEmpty || !cast.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !directors.isEmpty {
                    Text("Directed by \(directors.joined(separator: ", "))")
                }
                if !cast.isEmpty {
                    Text("With \(cast.joined(separator: ", "))")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 22))
            .foregroundStyle(palette.secondaryText.opacity(0.8))
        }
    }
}

/// Where the See all details pop-up sits beside the card it describes.
enum HomeRowBrowseDetailPopupPlacement {
    /// Clear space between the card and the pop-up. Generous enough that the
    /// focused card can grow and lift without running under it.
    static let gap: CGFloat = 48
    /// The pop-up keeps at least this far inside the visible grid.
    static let margin: CGFloat = 24

    /// The pop-up's top-leading corner, in the same space as `card` and
    /// `bounds`. It goes on the trailing side when it fits there, else the
    /// leading side, else whichever side has more room, and is kept inside
    /// `bounds`. Vertically it lines up with the card's top, moved up as needed
    /// to stay on screen.
    static func origin(card: CGRect, popup: CGSize, bounds: CGRect) -> CGPoint {
        let trailingRoom = bounds.maxX - card.maxX - gap - margin
        let leadingRoom = card.minX - bounds.minX - gap - margin
        let x: CGFloat
        if trailingRoom >= popup.width || (leadingRoom < popup.width && trailingRoom >= leadingRoom) {
            x = card.maxX + gap
        } else {
            x = card.minX - gap - popup.width
        }
        let minX = bounds.minX + margin, maxX = bounds.maxX - margin - popup.width
        let minY = bounds.minY + margin, maxY = bounds.maxY - margin - popup.height
        return CGPoint(
            x: max(minX, min(x, maxX)),
            y: max(minY, min(card.minY, maxY))
        )
    }
}
#endif
