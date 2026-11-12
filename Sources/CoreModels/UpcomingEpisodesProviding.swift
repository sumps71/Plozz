import Foundation

/// Optional capability: a provider that can list the not-yet-aired episodes of
/// series the signed-in server user has started watching.
///
/// Kept separate from ``MediaProvider`` (like ``WatchlistProviding``) so a backend
/// without a server-side notion of upcoming episodes simply doesn't conform, and
/// Home skips it rather than showing a misleading empty row.
///
/// Conformers return **real server items** — never schedule placeholders — so a
/// selected card opens the episode's ordinary detail page. Results are expected to
/// have passed ``UpcomingEpisodesPolicy/curated(_:now:calendar:)``.
public protocol UpcomingEpisodesProviding: Sendable {
    /// Every known future episode of a series the active server user has watched
    /// at least one episode of, earliest original air date first. Throws on a
    /// server failure; an empty result means there genuinely is nothing upcoming.
    func upcomingEpisodes(now: Date) async throws -> [MediaItem]
}

/// Pure rules for the Home "Upcoming Episodes" row, shared by every provider and
/// by the cross-account merge so ordering and de-duplication never drift.
public enum UpcomingEpisodesPolicy {
    /// Filters, de-duplicates and orders upcoming episodes.
    ///
    /// - Only `.episode` items with a ``MediaItem/releaseDate`` are kept: an item
    ///   with no air date can't be placed in date order, so it is dropped rather
    ///   than guessed.
    /// - "Future" means the episode's calendar day is **after** the viewer's local
    ///   today. `releaseDate` is a bare calendar day stored at UTC midnight (see
    ///   ``MediaItem/calendarDayReleaseDate(snapping:)``), so an episode dated today
    ///   may already have aired and is excluded.
    /// - Duplicates are removed first by item identity (same server item twice),
    ///   then by `(series, season, episode)` so two entries for one episode on the
    ///   same series collapse to the first.
    /// - Ordered by air date, then series title, season and episode number, then id
    ///   for a fully deterministic order.
    public static func curated(
        _ items: [MediaItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [MediaItem] {
        guard let todayUTC = calendarDayAtUTCMidnight(of: now, in: calendar) else { return [] }
        var seenIDs = Set<String>()
        var seenEpisodes = Set<EpisodeKey>()
        let kept = items.filter { item in
            guard item.kind == .episode,
                  let airDate = item.releaseDate,
                  airDate > todayUTC,
                  seenIDs.insert(identity(of: item)).inserted
            else { return false }
            if let key = EpisodeKey(item) {
                return seenEpisodes.insert(key).inserted
            }
            return true
        }
        return kept.sorted(by: isOrderedBefore)
    }

    /// The viewer's local calendar day for `date`, expressed the way
    /// `releaseDate` is stored (that day at 00:00 UTC), so the two compare as days.
    static func calendarDayAtUTCMidnight(of date: Date, in calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return utcCalendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }

    /// Episodes airing fewer than this many days from today show a countdown
    /// ("Tomorrow", "In 3 days", "Next week"); later ones show their air date.
    public static let countdownDayLimit = 14

    /// Whole calendar days from the viewer's local today until `airDate` (a bare
    /// day stored at UTC midnight): 1 for tomorrow, 0 for today, negative if past.
    public static func daysUntilAir(_ airDate: Date, now: Date, calendar: Calendar = .current) -> Int? {
        guard let today = calendarDayAtUTCMidnight(of: now, in: calendar) else { return nil }
        return utcCalendar.dateComponents([.day], from: today, to: airDate).day
    }

    private static let utcCalendar: Calendar = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        return utc
    }()

    static func isOrderedBefore(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        let lhsDate = lhs.releaseDate ?? .distantFuture
        let rhsDate = rhs.releaseDate ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        let lhsSeries = lhs.parentTitle ?? ""
        let rhsSeries = rhs.parentTitle ?? ""
        let seriesOrder = lhsSeries.localizedStandardCompare(rhsSeries)
        if seriesOrder != .orderedSame { return seriesOrder == .orderedAscending }
        let lhsSeason = lhs.seasonNumber ?? .max
        let rhsSeason = rhs.seasonNumber ?? .max
        if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
        let lhsEpisode = lhs.episodeNumber ?? .max
        let rhsEpisode = rhs.episodeNumber ?? .max
        if lhsEpisode != rhsEpisode { return lhsEpisode < rhsEpisode }
        return identity(of: lhs) < identity(of: rhs)
    }

    /// Item identity scoped to its source account, so two servers that happen to
    /// share an id never collapse into one card.
    private static func identity(of item: MediaItem) -> String {
        "\(item.sourceAccountID ?? ""):\(item.id)"
    }

    private struct EpisodeKey: Hashable {
        let account: String
        let seriesID: String
        let season: Int
        let episode: Int

        init?(_ item: MediaItem) {
            guard let seriesID = item.seriesID, !seriesID.isEmpty,
                  let season = item.seasonNumber,
                  let episode = item.episodeNumber
            else { return nil }
            self.account = item.sourceAccountID ?? ""
            self.seriesID = seriesID
            self.season = season
            self.episode = episode
        }
    }
}

public extension MediaItem {
    /// When an upcoming episode airs, as an Upcoming Episodes card shows it:
    /// "Tomorrow", "In 2 days" … "In 6 days", "Next week" (7–13 days), and the
    /// air date from ``UpcomingEpisodesPolicy/countdownDayLimit`` days on.
    ///
    /// The countdown is the system's relative-date wording, so it is localized
    /// without catalog strings (German "Übermorgen", Japanese "来週"). Days are
    /// counted from the viewer's local today, as ``UpcomingEpisodesPolicy`` does.
    func upcomingEpisodeAirLabel(  // l10n:content — system relative-date or date-format output
        now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        guard let releaseDate else { return nil }
        let components: DateComponents
        switch UpcomingEpisodesPolicy.daysUntilAir(releaseDate, now: now, calendar: calendar) {
        case let days? where (1...6).contains(days):
            components = DateComponents(day: days)
        case let days? where (7..<UpcomingEpisodesPolicy.countdownDayLimit).contains(days):
            components = DateComponents(weekOfMonth: 1)
        default:
            return releaseDateLabel
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: components)
    }

    /// The secondary caption an Upcoming Episodes card shows under the show name,
    /// e.g. `S2, E5 · In 3 days` or, two weeks or more out, `S2, E5 · Dec 20, 2026`
    /// (see ``upcomingEpisodeAirLabel(now:calendar:locale:)``).
    ///
    /// The episode name is never shown: the row is about which show returns and
    /// when, and an unaired episode's name is often a placeholder or a spoiler.
    func upcomingEpisodeCaption(  // l10n:content — numbering and date-format output
        now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        var parts: [String] = []
        if let numbering = seasonEpisodeLabel {
            parts.append(numbering)
        } else if let episodeNumber {
            parts.append("E\(episodeNumber)")  // l10n:content — hand-built numbering, matches seasonEpisodeLabel
        }
        if let airs = upcomingEpisodeAirLabel(now: now, calendar: calendar, locale: locale) {
            parts.append(airs)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
