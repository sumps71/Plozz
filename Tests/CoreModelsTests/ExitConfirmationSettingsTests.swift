import XCTest
@testable import CoreModels

/// Covers the "confirm exit after controls hide" window on `PlaybackSettings`:
/// default, 0.5s option steps, clamping/snapping, and decoding older payloads.
final class ExitConfirmationSettingsTests: XCTestCase {

    func testDefaultIsThreeSeconds() {
        XCTAssertEqual(PlaybackSettings.default.exitConfirmationSeconds, 3)
    }

    func testOptionsAreHalfSecondStepsFromOffToThree() {
        XCTAssertEqual(PlaybackSettings.exitConfirmationSecondsOptions, [0, 0.5, 1, 1.5, 2, 2.5, 3])
    }

    func testValuesAreClampedAndSnapped() {
        XCTAssertEqual(PlaybackSettings(exitConfirmationSeconds: -1).exitConfirmationSeconds, 0)
        XCTAssertEqual(PlaybackSettings(exitConfirmationSeconds: 9).exitConfirmationSeconds, 3)
        XCTAssertEqual(PlaybackSettings(exitConfirmationSeconds: 1.6).exitConfirmationSeconds, 1.5)
    }

    func testRoundTripsAndOlderPayloadGetsDefault() throws {
        var settings = PlaybackSettings.default
        settings.exitConfirmationSeconds = 1.5
        let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.exitConfirmationSeconds, 1.5)

        let legacy = try JSONSerialization.data(withJSONObject: ["seekWithoutPausing": false])
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSettings.self, from: legacy).exitConfirmationSeconds, 3)
    }
}
