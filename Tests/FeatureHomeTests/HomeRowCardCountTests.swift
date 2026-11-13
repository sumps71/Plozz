import XCTest
import CoreModels
@testable import FeatureHomeCore

@MainActor
final class HomeRowCardCountTests: XCTestCase {
    private func definition(_ id: String, kind: ServerHomeSection.Kind) -> HomeServerRowDefinition {
        .init(
            accountID: "server", serverName: "Media server", providerKind: .silo,
            section: .init(id: id, kind: kind, title: id)
        )
    }

    private func visibility(_ rows: [HomeServerRowDefinition]) -> HomeLibraryVisibility {
        .init(rowCustomization: .init(
            defaults: .custom, order: rows.map(\.id), shown: Set(rows.map(\.id)), serverRows: rows
        ))
    }

    private func items(_ count: Int) -> [MediaItem] {
        (0..<count).map { MediaItem(id: "item-\($0)", title: "Title \($0)", kind: .movie) }
    }

    private func sections(_ rows: [HomePresentationRow]) -> [LibrarySection] {
        rows.compactMap {
            guard case let .library(row) = $0.source else { return nil }
            return row.section
        }
    }

    func testRowsShowTheChosenNumberOfCardsAndKeepSeeAll() {
        let suggested = definition("suggested", kind: .recommendations)
        let content = HomeViewModel.Content(serverRows: [.init(definition: suggested, items: items(21))])
        for limit in HeroSettings.homeRowCardCountOptions {
            let row = sections(HomePresentationRow.resolve(
                rows: [], content: content, visibility: visibility([suggested]), cardLimit: limit
            )).first
            XCTAssertEqual(row?.items.count, limit)
            XCTAssertEqual(row?.items.first?.id, "item-0", "The row keeps its leading titles")
            XCTAssertEqual(row?.hasMore, limit < 21, "A trimmed row still offers See all")
        }
        let unlimited = sections(HomePresentationRow.resolve(
            rows: [], content: content, visibility: visibility([suggested])
        )).first
        XCTAssertEqual(unlimited?.items.count, 21, "No limit leaves the row as loaded (iPhone and iPad)")
    }

    func testShortRowsAreUntouched() {
        let suggested = definition("suggested", kind: .recommendations)
        let content = HomeViewModel.Content(serverRows: [.init(definition: suggested, items: items(5))])
        let row = sections(HomePresentationRow.resolve(
            rows: [], content: content, visibility: visibility([suggested]), cardLimit: 11
        )).first
        XCTAssertEqual(row?.items.count, 5)
        XCTAssertEqual(row?.hasMore, false)
    }

    func testServerContinueWatchingRowKeepsEveryTitle() {
        let resume = definition("resume", kind: .continueWatching)
        let content = HomeViewModel.Content(serverRows: [.init(definition: resume, items: items(30))])
        let row = sections(HomePresentationRow.resolve(
            rows: [], content: content, visibility: visibility([resume]), cardLimit: 11
        )).first
        XCTAssertEqual(row?.items.count, 30)
    }

    func testContinueWatchingAndUpcomingEpisodesAreNeverLimited() throws {
        func choice(_ kind: HomeGlobalRow) throws -> HomeRowChoice {
            try XCTUnwrap(HomeRowChoice.shared.first { $0.id == .global(kind) })
        }
        XCTAssertFalse(HomeRowCardCount.appliesLimit(to: try choice(.continueWatching)))
        XCTAssertFalse(HomeRowCardCount.appliesLimit(to: try choice(.upcomingEpisodes)))
        XCTAssertTrue(HomeRowCardCount.appliesLimit(to: try choice(.watchlist)))
        XCTAssertTrue(HomeRowCardCount.appliesLimit(to: try choice(.recentlyAdded)))

        let resumeOnly = CollectionSection(sources: [HomeContentSource(home: .continueWatching)])
        XCTAssertFalse(HomeRowCardCount.appliesLimit(to: HomeRowChoice(collectionSection: resumeOnly)))
        let mixed = CollectionSection(sources: [
            HomeContentSource(home: .continueWatching), HomeContentSource(home: .recentlyAdded)
        ])
        XCTAssertTrue(HomeRowCardCount.appliesLimit(to: HomeRowChoice(collectionSection: mixed)))
    }

    func testAppleTVPreviewsLoadEnoughForTheLargestOptionWhileOthersKeepTwenty() {
        XCTAssertEqual(HomeRowCardCount.largestPreviewLimit, 21)
        XCTAssertEqual(HomeRowCardCount.standardPreviewLimit, 20, "iPhone and iPad rows are unchanged")
        XCTAssertEqual(HomeViewModel(accounts: []).rowPreviewLimit, 20)
        XCTAssertEqual(HomeViewModel(accounts: [], rowPreviewLimit: 21).rowPreviewLimit, 21)
    }

    func testRecentlyAddedFillsTheLargerAppleTVPreview() {
        let candidates = items(30)
        let content = HomeViewModel.Content(latest: candidates, recentlyAddedCandidates: candidates)
        let visibility = HomeLibraryVisibility(rowCustomization: .init(
            defaults: .custom, order: [.global(.recentlyAdded)], shown: [.global(.recentlyAdded)]
        ))
        func recent(previewLimit: Int, cardLimit: Int?) -> HomeRow? {
            HomePresentationRow.resolve(
                rows: [HomeRow(kind: .recentlyAdded, items: candidates)], content: content,
                visibility: visibility, previewLimit: previewLimit, cardLimit: cardLimit
            ).compactMap {
                guard case let .home(row) = $0.source else { return nil }
                return row
            }.first
        }
        XCTAssertEqual(recent(previewLimit: 20, cardLimit: nil)?.items.count, 20, "Unchanged default")
        XCTAssertEqual(recent(previewLimit: 21, cardLimit: 21)?.items.count, 21)
        XCTAssertEqual(recent(previewLimit: 21, cardLimit: 11)?.items.count, 11)
        XCTAssertEqual(recent(previewLimit: 21, cardLimit: 11)?.hasMore, true)
    }
}
