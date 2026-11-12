import CoreModels
import CoreNetworking
import XCTest
@testable import ProviderJellyfin

/// `/Shows/Upcoming` behaviour verified against Jellyfin's
/// `TvShowsController.GetUpcomingEpisodes`: the floor is yesterday (UTC),
/// `TotalRecordCount` is the page size rather than the total, and there is no
/// played filter — so Plozz pages, filters and checks played state itself.
final class JellyfinUpcomingEpisodesTests: XCTestCase {
    /// 2026-11-12 20:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_513_600)
    private let itemsPath = "/Users/viewer/Items"

    private func provider(_ http: StubHTTPClient, kind: ProviderKind = .jellyfin) -> JellyfinProvider {
        JellyfinProvider(
            session: UserSession(
                server: MediaServer(
                    id: "server", name: "Home", baseURL: URL(string: "https://media.test/base")!,
                    provider: kind
                ),
                userID: "viewer", userName: "Viewer", deviceID: "test-device", accessToken: "TEST_TOKEN"
            ),
            http: http
        )
    }

    private func episode(
        _ id: String, series: String = "s1", number: Int = 1, premiere: String? = "2026-12-01"
    ) -> String {
        let date = premiere.map { #","PremiereDate":"\#($0)T00:00:00.0000000Z""# } ?? ""
        return #"{"Id":"\#(id)","Name":"Title \#(id)","Type":"Episode","SeriesId":"\#(series)","#
            + #""SeriesName":"Show \#(series)","ParentIndexNumber":1,"IndexNumber":\#(number),"#
            + #""LocationType":"Virtual"\#(date)}"#
    }

    /// Mirrors the server: `TotalRecordCount` is the count of THIS page.
    private func page(_ items: [String]) -> String {
        #"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(items.count)}"#
    }

    private func stubPlayed(_ http: StubHTTPClient, series: String, played: Bool?) {
        let body: String
        if let played {
            body = #"{"Items":[{"Id":"played-\#(series)","Type":"Episode","SeriesId":"\#(series)","#
                + #""UserData":{"Played":\#(played)}}]}"#
        } else {
            body = #"{"Items":[]}"#
        }
        http.stub(
            pathSuffix: itemsPath, requiring: [URLQueryItem(name: "ParentId", value: series)], json: body
        )
    }

    private func upcomingQueries(_ http: StubHTTPClient) -> [[URLQueryItem]] {
        zip(http.sentPaths, http.sentQueryItems).compactMap { path, query in
            path == "/Shows/Upcoming" ? query : nil
        }
    }

    private func playedCheckSeries(_ http: StubHTTPClient) -> [String] {
        zip(http.sentPaths, http.sentQueryItems).compactMap { path, query in
            path == itemsPath ? query.first { $0.name == "ParentId" }?.value : nil
        }.sorted()
    }

    func testPagesUntilAShortPageBecauseTotalCountOnlyCountsThePage() async throws {
        let http = StubHTTPClient()
        let first = (0..<100).map { episode("e\($0)", number: $0 + 1) }
        let second = (100..<103).map { episode("e\($0)", number: $0 + 1) }
        http.stubSequence(pathSuffix: "/Shows/Upcoming", jsons: [page(first), page(second)])
        stubPlayed(http, series: "s1", played: true)

        let items = try await provider(http).upcomingEpisodes(now: now)

        XCTAssertEqual(items.count, 103)
        XCTAssertEqual(items.compactMap(\.episodeNumber), Array(1...103))
        let queries = upcomingQueries(http)
        XCTAssertEqual(queries.map { $0.first { $0.name == "StartIndex" }?.value }, ["0", "100"])
        XCTAssertTrue(queries.allSatisfy { $0.first { $0.name == "UserId" }?.value == "viewer" })
        XCTAssertTrue(queries.allSatisfy { $0.first { $0.name == "Limit" }?.value == "100" })
        // One played-state lookup per series, not per episode.
        XCTAssertEqual(playedCheckSeries(http), ["s1"])
    }

    func testKeepsOnlyFutureDatedEpisodesOfSeriesWithAPlayedEpisode() async throws {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/Shows/Upcoming", json: page([
            episode("later", series: "watched", number: 2, premiere: "2026-12-08"),
            episode("sooner", series: "watched", number: 1, premiere: "2026-11-20"),
            episode("unwatched", series: "unwatched", premiere: "2026-11-21"),
            episode("filter-ignored", series: "lying", premiere: "2026-11-22"),
            // The server's floor is yesterday (UTC); these have already aired.
            episode("aired", series: "aired-only", premiere: "2026-11-11"),
            episode("undated", series: "undated-only", premiere: nil),
        ]))
        stubPlayed(http, series: "watched", played: true)
        stubPlayed(http, series: "unwatched", played: nil)
        stubPlayed(http, series: "lying", played: false)

        let items = try await provider(http).upcomingEpisodes(now: now)

        XCTAssertEqual(items.map(\.id), ["sooner", "later"])
        XCTAssertEqual(items.first?.kind, .episode)
        XCTAssertEqual(items.first?.parentTitle, "Show watched")
        XCTAssertEqual(items.first?.seriesID, "watched")
        XCTAssertEqual(items.first?.releaseDate, MediaItem.calendarDayReleaseDate(from: "2026-11-20"))
        // Virtual (unaired) episodes are never offered as playable.
        XCTAssertEqual(items.first?.locallyValidatedPlayableSource, false)
        // Series with nothing upcoming are never checked.
        XCTAssertEqual(playedCheckSeries(http), ["lying", "unwatched", "watched"])
        let check = try XCTUnwrap(http.queryItems(forPathSuffix: itemsPath))
        XCTAssertTrue(check.contains(URLQueryItem(name: "Filters", value: "IsPlayed")))
        XCTAssertTrue(check.contains(URLQueryItem(name: "IncludeItemTypes", value: "Episode")))
        XCTAssertTrue(check.contains(URLQueryItem(name: "Recursive", value: "true")))
    }

    func testAnItemRepeatedAcrossPagesAppearsOnce() async throws {
        let http = StubHTTPClient()
        let first = (0..<100).map { episode("e\($0)", number: $0 + 1) }
        let second = [episode("e99", number: 100), episode("e100", number: 101)]
        http.stubSequence(pathSuffix: "/Shows/Upcoming", jsons: [page(first), page(second)])
        stubPlayed(http, series: "s1", played: true)

        let items = try await provider(http).upcomingEpisodes(now: now)

        XCTAssertEqual(items.count, 101)
        XCTAssertEqual(Set(items.map(\.id)).count, 101)
    }

    func testAServerIgnoringStartIndexFailsClosedInsteadOfLooping() async {
        let http = StubHTTPClient()
        http.stub(
            pathSuffix: "/Shows/Upcoming",
            json: page((0..<100).map { episode("e\($0)", number: $0 + 1) })
        )
        stubPlayed(http, series: "s1", played: true)

        do {
            _ = try await provider(http).upcomingEpisodes(now: now)
            XCTFail("A non-advancing feed must not become a truncated row.")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
        XCTAssertEqual(upcomingQueries(http).count, 2)
    }

    func testServerErrorsSurfaceInsteadOfAnEmptyRow() async {
        let cases: [(status: Int, expected: AppError)] = [(500, .invalidResponse), (401, .unauthorized)]
        for (status, expected) in cases {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Shows/Upcoming", json: "{}", status: status)
            do {
                _ = try await provider(http).upcomingEpisodes(now: now)
                XCTFail("HTTP \(status) must not read as nothing upcoming.")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
            }
        }
    }

    func testAFailedPlayedLookupFailsTheRow() async {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/Shows/Upcoming", json: page([episode("e1", series: "s1")]))
        http.stub(
            pathSuffix: itemsPath, requiring: [URLQueryItem(name: "ParentId", value: "s1")],
            json: "{}", status: 503
        )
        do {
            _ = try await provider(http).upcomingEpisodes(now: now)
            XCTFail("An unknown played state must not admit or hide the series silently.")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
    }

    func testEmbyReturnsNothingAndSendsNoRequest() async throws {
        let http = StubHTTPClient()
        let items = try await provider(http, kind: .emby).upcomingEpisodes(now: now)
        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(http.sentPaths.isEmpty)
    }
}
