import XCTest
import CoreModels
@testable import FeatureHomeCore

/// The opt-in Upcoming Episodes row: merged across `UpcomingEpisodesProviding`
/// accounts in air-date order, requested only while enabled, and resilient to
/// one account failing.
@MainActor
final class HomeAggregatorUpcomingEpisodesTests: XCTestCase {
    private let enabled = HomeLibraryVisibility(
        rowCustomization: HomeRowCustomization(shown: [.global(.upcomingEpisodes)])
    )

    func testUpcomingEpisodesUsesTheContinueWatchingCardWithShowLogos() {
        XCTAssertTrue(HomeRowKind.upcomingEpisodes.usesContinueWatchingCard)
        XCTAssertTrue(HomeRowKind.continueWatching.usesContinueWatchingCard)
        for kind: HomeRowKind in [.watchlist, .recentlyAdded, .libraries] {
            XCTAssertFalse(kind.usesContinueWatchingCard, "\(kind)")
            XCTAssertFalse(kind.showsSeriesArtwork(continueWatchingUsesSeriesArtwork: true), "\(kind)")
        }
        // Upcoming always shows the show logo; Continue Watching follows its setting.
        for setting in [false, true] {
            XCTAssertTrue(HomeRowKind.upcomingEpisodes.showsSeriesArtwork(continueWatchingUsesSeriesArtwork: setting))
            XCTAssertEqual(
                HomeRowKind.continueWatching.showsSeriesArtwork(continueWatchingUsesSeriesArtwork: setting), setting
            )
        }
    }

    func testMergesAccountsInAirDateOrderAndTagsEachSource() async {
        let a = UpcomingStub(episodes: [episode("a1", daysAhead: 3), episode("a2", daysAhead: 10)])
        let b = UpcomingStub(episodes: [episode("b1", daysAhead: 5)])
        let content = await HomeAggregator().content(
            from: [resolved("acct-a", provider: a), resolved("acct-b", provider: b)],
            visibility: enabled
        )
        XCTAssertEqual(content.upcomingEpisodes.map(\.id), ["a1", "b1", "a2"])
        XCTAssertEqual(content.upcomingEpisodes.map(\.sourceAccountID), ["acct-a", "acct-b", "acct-a"])
    }

    func testRowOffSendsNoRequests() async {
        let stub = UpcomingStub(episodes: [episode("a1", daysAhead: 3)])
        for visibility in [HomeLibraryVisibility(), .default] {
            let content = await HomeAggregator().content(
                from: [resolved("acct-a", provider: stub)], visibility: visibility
            )
            XCTAssertTrue(content.upcomingEpisodes.isEmpty)
        }
        XCTAssertEqual(stub.calls, 0)
    }

    func testProvidersWithoutTheCapabilityAreSkippedAndDoNotHoldTheRow() async {
        let stub = UpcomingStub(episodes: [episode("a1", daysAhead: 3)])
        let progress = ProgressLog()
        let content = await HomeAggregator().content(
            from: [resolved("acct-a", provider: stub), resolved("acct-plex", provider: PlainStub())],
            visibility: enabled,
            onProgress: { await progress.record($0) }
        )
        XCTAssertEqual(content.upcomingEpisodes.map(\.id), ["a1"])
        let last = await progress.last
        XCTAssertEqual(last?.loadingRows.contains(.upcomingEpisodes), false)
        XCTAssertNil(last?.failures[.upcomingEpisodes])
    }

    func testOneFailingAccountKeepsOthersAndReportsTheFailure() async {
        let failing = UpcomingStub(episodes: [], error: .serverUnreachable)
        let working = UpcomingStub(episodes: [episode("b1", daysAhead: 4)])
        let progress = ProgressLog()
        let content = await HomeAggregator().content(
            from: [resolved("acct-a", provider: failing), resolved("acct-b", provider: working)],
            visibility: enabled,
            onProgress: { await progress.record($0) }
        )
        XCTAssertEqual(content.upcomingEpisodes.map(\.id), ["b1"])
        let last = await progress.last
        XCTAssertEqual(last?.failures[.upcomingEpisodes], .serverUnreachable)
        XCTAssertEqual(last?.loadingRows.contains(.upcomingEpisodes), false)
    }

    func testRowAppearsOnlyWhenEnabledAndUsesLandscapeCards() {
        var content = HomeViewModel.Content()
        content.upcomingEpisodes = [episode("a1", daysAhead: 3)]
        let off = HomeRow.rows(
            for: content, isLibraryVisible: { _ in true },
            isGlobalRowEnabled: HomeLibraryVisibility().isGlobalRowEnabled
        )
        XCTAssertFalse(off.contains { $0.kind == .upcomingEpisodes })
        let on = HomeRow.rows(
            for: content, isLibraryVisible: { _ in true },
            isGlobalRowEnabled: enabled.isGlobalRowEnabled
        )
        let row = on.first { $0.kind == .upcomingEpisodes }
        XCTAssertEqual(row?.items.map(\.id), ["a1"])
        XCTAssertEqual(row?.style, .landscape)
        XCTAssertFalse(row?.hasMore ?? true)

        let presented = HomePresentationRow.resolve(rows: on, content: content, visibility: enabled)
        XCTAssertTrue(presented.contains { $0.id == .global(.upcomingEpisodes) })
    }

    func testFailedEnabledRowStillRendersItsFailure() {
        let rows = HomeRow.rows(
            for: HomeViewModel.Content(), isLibraryVisible: { _ in true },
            isGlobalRowEnabled: enabled.isGlobalRowEnabled,
            failures: [.upcomingEpisodes: .serverUnreachable]
        )
        XCTAssertEqual(rows.first { $0.kind == .upcomingEpisodes }?.failure, .serverUnreachable)
    }

    // MARK: - Helpers

    private func episode(_ id: String, daysAhead: Int) -> MediaItem {
        let date = MediaItem.calendarDayReleaseDate(
            snapping: Date().addingTimeInterval(TimeInterval(daysAhead) * 86_400)
        )
        return MediaItem(
            id: id, title: "Episode \(id)", kind: .episode, parentTitle: "Show \(id)",
            seasonNumber: 1, episodeNumber: 1, releaseDate: date, seriesID: "series-\(id)"
        )
    }

    private func resolved(_ id: String, provider: any MediaProvider) -> ResolvedAccount {
        let server = MediaServer(
            id: "srv-\(id)", name: id, baseURL: URL(string: "http://host")!, provider: provider.kind
        )
        let account = Account(id: id, server: server, userID: "u-\(id)", userName: id, deviceID: "d-\(id)")
        return ResolvedAccount(account: account, provider: provider)
    }
}

private actor ProgressLog {
    private(set) var last: HomeAggregator.Progress?
    func record(_ progress: HomeAggregator.Progress) { last = progress }
}

/// A provider that also conforms to `UpcomingEpisodesProviding`.
private final class UpcomingStub: MediaProvider, UpcomingEpisodesProviding, @unchecked Sendable {
    let kind: ProviderKind = .jellyfin
    let session = UserSession(
        server: MediaServer(id: "s", name: "Home", baseURL: URL(string: "http://host")!, provider: .jellyfin),
        userID: "u", userName: "User", deviceID: "d", accessToken: "TOKEN"
    )
    private let episodes: [MediaItem]
    private let error: AppError?
    private let lock = NSLock()
    private var callCount = 0
    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    init(episodes: [MediaItem], error: AppError? = nil) {
        self.episodes = episodes
        self.error = error
    }

    func upcomingEpisodes(now: Date) async throws -> [MediaItem] {
        lock.lock()
        callCount += 1
        lock.unlock()
        if let error { throw error }
        return episodes
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}

/// A provider with no upcoming-episodes capability.
private final class PlainStub: MediaProvider, @unchecked Sendable {
    let kind: ProviderKind = .plex
    let session = UserSession(
        server: MediaServer(id: "s", name: "Home", baseURL: URL(string: "http://host")!, provider: .plex),
        userID: "u", userName: "User", deviceID: "d", accessToken: "TOKEN"
    )
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
