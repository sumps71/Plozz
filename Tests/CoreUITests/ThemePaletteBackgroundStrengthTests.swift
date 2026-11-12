#if canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import CoreUI

final class ThemePaletteBackgroundStrengthTests: XCTestCase {
    private func brightness(_ color: Color) -> Float {
        let resolved = color.resolve(in: EnvironmentValues())
        return (resolved.red + resolved.green + resolved.blue) / 3
    }

    func testFullStrengthLeavesThePaletteUnchanged() {
        for palette in [ThemePalette.pureBlack, .dark, .light] {
            XCTAssertEqual(palette.adjustingBackground(strength: 1), palette)
        }
    }

    func testLowerStrengthSoftensThePageTowardGreyAndLeavesTextAlone() {
        let black = ThemePalette.pureBlack.adjustingBackground(strength: 0.6)
        XCTAssertGreaterThan(brightness(black.backgroundBase), brightness(ThemePalette.pureBlack.backgroundBase) + 0.1,
                             "Black becomes charcoal")
        let light = ThemePalette.light.adjustingBackground(strength: 0.6)
        XCTAssertLessThan(brightness(light.backgroundBase), brightness(ThemePalette.light.backgroundBase) - 0.1,
                          "Light becomes a greyer white")
        XCTAssertEqual(black.primaryText, ThemePalette.pureBlack.primaryText)
        XCTAssertEqual(black.isLight, ThemePalette.pureBlack.isLight)
        XCTAssertLessThan(brightness(black.backgroundBase), 0.5, "Even softened, Black stays a dark page")
    }
}
#endif
