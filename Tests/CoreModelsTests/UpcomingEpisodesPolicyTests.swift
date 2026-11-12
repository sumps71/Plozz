import XCTest
@testable import CoreModels

final class UpcomingEpisodesPolicyTests: XCTestCase {
    /// 2026-11-12 20:00 UTC: still the 12th in Los Angeles, already the 13th in Auckland.
    private let now = Date(timeIntervalSince1970: 1_794_513_600)

    private func day(_ value: String) -> Date {
        MediaItem.calendarDayReleaseDate(from: value)!
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func episode(
        _ id: String, _ date: String?, series: String = "series-a", show: String = "Show A",
        season: Int? = 1, number: Int? = nil, account: String? = nil, kind: MediaItemKind = .episode
    ) -> MediaItem {
        var item = MediaItem(
            id: id, title: "Title \(id)", kind: kind, parentTitle: show,
            seasonNumber: season, episodeNumber: number,
            releaseDate: date.map(day), seriesID: series
        )
        item.sourceAccountID = account
        return item
    }

    func testNowFixtureIsTheIntendedInstant() {
        XCTAssertEqual(
            now.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)), "2026-11-12T20:00:00Z"
        )
    }

    func testKeepsOnlyDatedFutureEpisodes() {
        let items = [
            episode("past", "2026-11-01", number: 1),
            episode("yesterday", "2026-11-11", number: 2),
            episode("today", "2026-11-12", number: 3),
            episode("undated", nil, number: 4),
            episode("movie", "2026-12-01", kind: .movie),
            episode("tomorrow", "2026-11-13", number: 5),
        ]
        let result = UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(result.map(\.id), ["tomorrow"])
    }

    func testFutureIsJudgedByTheViewersLocalDay() {
        let items = [episode("13th", "2026-11-13", number: 1), episode("14th", "2026-11-14", number: 2)]
        XCTAssertEqual(
            UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("America/Los_Angeles")).map(\.id),
            ["13th", "14th"]
        )
        // Auckland is already on the 13th, so an episode dated the 13th may have aired.
        XCTAssertEqual(
            UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("Pacific/Auckland")).map(\.id),
            ["14th"]
        )
    }

    func testSortsByAirDateThenShowSeasonAndEpisode() {
        let items = [
            episode("late", "2026-12-20", number: 1),
            episode("b-s2e1", "2026-12-01", series: "b", show: "Show B", season: 2, number: 1),
            episode("a-s1e2", "2026-12-01", series: "a", show: "Show A", season: 1, number: 2),
            episode("a-s1e1", "2026-12-01", series: "a", show: "Show A", season: 1, number: 1),
            episode("early", "2026-11-20", series: "c", show: "Show C", number: 9),
        ]
        let result = UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("UTC"))
        XCTAssertEqual(result.map(\.id), ["early", "a-s1e1", "a-s1e2", "b-s2e1", "late"])
    }

    func testRemovesDuplicateItemsAndDuplicateEpisodeNumbers() {
        let items = [
            episode("one", "2026-11-20", number: 1),
            episode("one", "2026-11-20", number: 1),
            episode("one-again", "2026-11-21", number: 1),
            episode("two", "2026-11-27", number: 2),
        ]
        let result = UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("UTC"))
        XCTAssertEqual(result.map(\.id), ["one", "two"])
    }

    func testDoesNotCollapseTheSameIDsFromDifferentAccounts() {
        let items = [
            episode("shared", "2026-11-20", number: 1, account: "server-a"),
            episode("shared", "2026-11-20", number: 1, account: "server-b"),
        ]
        let result = UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("UTC"))
        XCTAssertEqual(result.map(\.sourceAccountID), ["server-a", "server-b"])
    }

    func testEpisodesWithoutNumbersAreKeptByIdentityOnly() {
        let items = [
            episode("special-1", "2026-11-20", season: nil, number: nil),
            episode("special-2", "2026-11-20", season: nil, number: nil),
        ]
        XCTAssertEqual(
            UpcomingEpisodesPolicy.curated(items, now: now, calendar: calendar("UTC")).map(\.id),
            ["special-1", "special-2"]
        )
    }

    func testCaptionShowsNumberingDateAndTitle() throws {
        let item = MediaItem(
            id: "e", title: "The Reckoning", kind: .episode, parentTitle: "Show A",
            seasonNumber: 2, episodeNumber: 5, releaseDate: day("2026-11-20"), seriesID: "a"
        )
        let date = try XCTUnwrap(item.releaseDateLabel)
        XCTAssertEqual(item.upcomingEpisodeCaption(hidesTitle: false), "S2, E5 · \(date) · The Reckoning")
        XCTAssertEqual(item.upcomingEpisodeCaption(hidesTitle: true), "S2, E5 · \(date)")
    }

    func testCaptionOmitsMissingPartsAndRepeatedShowName() {
        let item = MediaItem(
            id: "e", title: "Show A", kind: .episode, parentTitle: "Show A", episodeNumber: 3
        )
        XCTAssertEqual(item.upcomingEpisodeCaption(hidesTitle: false), "E3")
        let bare = MediaItem(id: "b", title: " ", kind: .episode)
        XCTAssertNil(bare.upcomingEpisodeCaption(hidesTitle: false))
    }

    // MARK: - Opt-in row visibility

    func testUpcomingEpisodesRowIsOffByDefaultInEveryPreset() {
        XCTAssertFalse(HomeLibraryVisibility().isGlobalRowEnabled(.upcomingEpisodes))
        XCTAssertFalse(HomeLibraryVisibility.default.isGlobalRowEnabled(.upcomingEpisodes))
        for defaults in HomeRowCustomization.Defaults.allCases {
            var customization = HomeRowCustomization(defaults: defaults)
            if defaults == .matchServer {
                customization.resolvedDefaults = .init(
                    mode: .combined, order: HomeRowChoice.shared.map(\.id)
                )
            }
            let visibility = HomeLibraryVisibility(rowCustomization: customization)
            XCTAssertFalse(visibility.isGlobalRowEnabled(.upcomingEpisodes), "\(defaults)")
            XCTAssertFalse(
                customization.isVisible(.global(.upcomingEpisodes), providerDefault: true), "\(defaults)"
            )
        }
    }

    func testExistingGlobalRowsKeepTheirDefaults() {
        let legacy = HomeLibraryVisibility()
        for row in HomeGlobalRow.allCases where !row.isOptIn {
            XCTAssertTrue(legacy.isGlobalRowEnabled(row), "\(row)")
        }
        let choice = HomeRowChoice.shared.first { $0.id == .global(.upcomingEpisodes) }
        XCTAssertEqual(choice?.isProviderDefault, false)
        XCTAssertEqual(choice?.isLegacyDefault, false)
        XCTAssertFalse(legacy.isHomeRowVisible(choice!))
    }

    func testExplicitlyShownRowIsEnabledAndCanBeHiddenAgain() {
        var visibility = HomeLibraryVisibility(
            rowCustomization: HomeRowCustomization(shown: [.global(.upcomingEpisodes)])
        )
        XCTAssertTrue(visibility.isGlobalRowEnabled(.upcomingEpisodes))
        visibility.setGlobalRowEnabled(false, for: .upcomingEpisodes)
        XCTAssertFalse(visibility.isGlobalRowEnabled(.upcomingEpisodes))
    }

    func testCatalogOffersTheRowOnlyWithAJellyfinLibraryAndTheArrangerEnablesIt() throws {
        func library(_ kind: ProviderKind) -> AggregatedLibrary {
            AggregatedLibrary(
                accountID: "\(kind.rawValue)-account", accountName: "Viewer", serverName: "Server",
                providerKind: kind, library: MediaLibrary(id: "shows", title: "Shows", kind: .series)
            )
        }
        let plexOnly = HomeSectionCatalog(libraries: [library(.plex)])
        XCTAssertFalse(plexOnly.choices.contains { $0.id == .global(.upcomingEpisodes) })

        let withJellyfin = HomeSectionCatalog(libraries: [library(.plex), library(.jellyfin)])
        XCTAssertTrue(withJellyfin.choices.contains { $0.id == .global(.upcomingEpisodes) })

        let legacy = HomeLibraryVisibility()
        XCTAssertFalse(withJellyfin.sections(in: legacy).enabled.contains(.global(.upcomingEpisodes)))
        let enabled = try withJellyfin.settingVisible(true, id: .global(.upcomingEpisodes), in: legacy)
        XCTAssertTrue(enabled.isGlobalRowEnabled(.upcomingEpisodes))
        for row in HomeGlobalRow.allCases where !row.isOptIn {
            XCTAssertEqual(enabled.isGlobalRowEnabled(row), legacy.isGlobalRowEnabled(row), "\(row)")
        }
    }
}
