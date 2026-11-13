import XCTest
import CoreModels

final class EpisodeSequenceTests: XCTestCase {
    private func ep(_ id: String, s: Int, e: Int) -> MediaItem {
        MediaItem(id: id, title: id, kind: .episode, seasonNumber: s, episodeNumber: e)
    }

    func testNeighborsMidSeason() {
        let pool = [ep("e1", s: 1, e: 1), ep("e2", s: 1, e: 2), ep("e3", s: 1, e: 3)]
        let n = EpisodeSequence.neighbors(of: pool[1], in: pool)
        XCTAssertEqual(n.previous?.id, "e1")
        XCTAssertEqual(n.next?.id, "e3")
    }

    func testNeighborsRollsIntoNextSeason() {
        let pool = [ep("e1", s: 1, e: 1), ep("e2", s: 1, e: 2), ep("p1", s: 2, e: 1)]
        let n = EpisodeSequence.neighbors(of: pool[1], in: pool)
        XCTAssertEqual(n.next?.id, "p1")
    }

    func testFirstHasNoPrevious() {
        let pool = [ep("e1", s: 1, e: 1), ep("e2", s: 1, e: 2)]
        let n = EpisodeSequence.neighbors(of: pool[0], in: pool)
        XCTAssertNil(n.previous)
        XCTAssertEqual(n.next?.id, "e2")
    }

    func testLastHasNoNext() {
        let pool = [ep("e1", s: 1, e: 1), ep("e2", s: 1, e: 2)]
        let n = EpisodeSequence.neighbors(of: pool[1], in: pool)
        XCTAssertEqual(n.previous?.id, "e1")
        XCTAssertNil(n.next)
    }

    func testUnsortedInputAndMissing() {
        let pool = [ep("e3", s: 1, e: 3), ep("e1", s: 1, e: 1), ep("e2", s: 1, e: 2)]
        XCTAssertEqual(EpisodeSequence.neighbors(of: pool[0], in: pool).previous?.id, "e2")
        let missing = MediaItem(id: "x", title: "x", kind: .episode)
        XCTAssertNil(EpisodeSequence.neighbors(of: missing, in: pool).next)
    }

    // MARK: - Playable next episode

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testAiredEpisodeIsPlayableNext() {
        var next = ep("e2", s: 1, e: 2)
        next.releaseDate = day(2026, 11, 5)
        XCTAssertTrue(EpisodeSequence.isPlayableNext(next, now: day(2026, 11, 12), calendar: utc))
    }

    func testEpisodeAiringTodayIsPlayableNext() {
        var next = ep("e2", s: 1, e: 2)
        next.releaseDate = day(2026, 11, 12)
        let evening = day(2026, 11, 12).addingTimeInterval(20 * 3600)
        XCTAssertTrue(EpisodeSequence.isPlayableNext(next, now: evening, calendar: utc))
    }

    func testUnairedEpisodeIsNotPlayableNext() {
        var next = ep("e2", s: 1, e: 2)
        next.releaseDate = day(2026, 11, 13)
        XCTAssertFalse(EpisodeSequence.isPlayableNext(next, now: day(2026, 11, 12), calendar: utc))
    }

    func testUnairedUsesTheViewersLocalDay() {
        // 11 Nov 23:00 in Chicago is already 12 Nov in UTC; the 12 Nov episode
        // has not aired for this viewer yet.
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        var next = ep("e2", s: 1, e: 2)
        next.releaseDate = day(2026, 11, 12)
        let now = day(2026, 11, 12).addingTimeInterval(5 * 3600)
        XCTAssertFalse(EpisodeSequence.isPlayableNext(next, now: now, calendar: chicago))
    }

    func testVirtualMissingEpisodeIsNotPlayableNext() {
        var next = ep("e2", s: 1, e: 2)
        next.releaseDate = day(2026, 1, 1)
        next.locallyValidatedPlayableSource = false
        XCTAssertFalse(EpisodeSequence.isPlayableNext(next, now: day(2026, 11, 12), calendar: utc))
    }

    func testScheduledPlaceholderIsNotPlayableNext() {
        var next = ep("e2", s: 1, e: 2)
        next.scheduledAirDate = day(2026, 11, 20)
        XCTAssertFalse(EpisodeSequence.isPlayableNext(next, now: day(2026, 11, 12), calendar: utc))
    }

    func testEpisodeWithoutAirDateIsPlayableNext() {
        XCTAssertTrue(EpisodeSequence.isPlayableNext(ep("e2", s: 1, e: 2), now: day(2026, 11, 12), calendar: utc))
    }
}
