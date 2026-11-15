@testable import CoreUI
import XCTest

@MainActor
final class MediaRowFocusTrackerTests: XCTestCase {
    private final class Row {}

    /// A card's long-press menu takes focus without it reaching another row, so
    /// the tracker keeps the row and nothing tells it to scroll back.
    func testFocusStayingWithinARowDoesNotLeaveIt() {
        let tracker = MediaRowFocusTracker()
        let row = ObjectIdentifier(Row())
        tracker.enter(row)
        let before = tracker.focusedRow
        tracker.enter(row)
        XCTAssertEqual(tracker.focusedRow, row)
        XCTAssertFalse(MediaRowFocusTracker.focusLeft(row, from: before, to: tracker.focusedRow))
    }

    func testOnlyTheRowFocusLeftResets() {
        let first = Row(), second = Row(), third = Row()
        let a = ObjectIdentifier(first), b = ObjectIdentifier(second), c = ObjectIdentifier(third)
        let tracker = MediaRowFocusTracker()
        tracker.enter(a)
        tracker.enter(b)
        XCTAssertEqual(tracker.focusedRow, b)

        XCTAssertTrue(MediaRowFocusTracker.focusLeft(a, from: a, to: b))
        XCTAssertFalse(MediaRowFocusTracker.focusLeft(b, from: a, to: b), "the row gaining focus stays put")
        XCTAssertFalse(MediaRowFocusTracker.focusLeft(c, from: a, to: b), "an untouched row isn't moved")
        XCTAssertFalse(MediaRowFocusTracker.focusLeft(a, from: nil, to: a), "first focus resets nothing")
    }
}
