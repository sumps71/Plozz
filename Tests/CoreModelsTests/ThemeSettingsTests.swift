import XCTest
@testable import CoreModels

final class ThemeSettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "ThemeSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultIsBlackWhenEmpty() {
        let store = ThemeSettingsStore(defaults: makeDefaults())
        XCTAssertEqual(store.load(), .pureBlack)
        XCTAssertEqual(AppTheme.default, .pureBlack)
    }

    /// An install that already chose Dark must keep it. The default moved to
    /// Black, and a stored choice has to outrank a changed default or the theme
    /// would appear to reset itself on update.
    func testStoredDarkSurvivesTheDefaultMoving() {
        let defaults = makeDefaults()
        defaults.set(AppTheme.dark.rawValue, forKey: "com.plozz.appTheme")
        XCTAssertEqual(ThemeSettingsStore(defaults: defaults).load(), .dark)
    }

    func testRoundTripForEveryTheme() {
        let defaults = makeDefaults()
        let store = ThemeSettingsStore(defaults: defaults)
        for theme in AppTheme.allCases {
            store.save(theme)
            XCTAssertEqual(store.load(), theme, "\(theme) did not round-trip")
            // A fresh store over the same defaults must read the same value.
            XCTAssertEqual(ThemeSettingsStore(defaults: defaults).load(), theme)
        }
    }

    func testCorruptValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("not-a-real-theme", forKey: "com.plozz.appTheme")
        XCTAssertEqual(ThemeSettingsStore(defaults: defaults).load(), .default)
    }

    @MainActor
    func testGradientDefaultsOnAndPersistsIndependentlyForEveryThemeAndProfile() {
        let defaults = makeDefaults()
        let primary = ThemeSettingsStore(defaults: defaults)
        let other = ThemeSettingsStore(defaults: defaults, namespace: "other")
        let model = ThemeSettingsModel(store: primary)
        XCTAssertTrue(model.gradientEnabled)
        for theme in AppTheme.allCases {
            model.theme = theme
            model.gradientEnabled = false
            XCTAssertFalse(ThemeSettingsModel(store: primary).gradientEnabled)
            XCTAssertEqual(primary.load(), theme)
            XCTAssertTrue(other.loadGradientEnabled())
            model.gradientEnabled = true
            XCTAssertTrue(primary.loadGradientEnabled())
        }
        model.gradientEnabled = false
        let snapshot = ProfileSettingsTransfer.capture(namespace: nil, defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "other", defaults: defaults)
        XCTAssertFalse(other.loadGradientEnabled())
        other.saveGradientEnabled(true)
        XCTAssertFalse(primary.loadGradientEnabled())
        XCTAssertTrue(other.loadGradientEnabled())
    }

    func testOpacityDefaultsToTodaysLookAndPersistsPerProfile() {
        let defaults = makeDefaults()
        let primary = ThemeSettingsStore(defaults: defaults)
        let other = ThemeSettingsStore(defaults: defaults, namespace: "other")
        XCTAssertEqual(primary.loadOpacity(), .default)
        XCTAssertEqual(ThemeOpacitySettings.default.backgroundStrength(for: .black), 100)
        XCTAssertEqual(ThemeOpacitySettings.default.artworkBehindPage, 0, "Artwork behind page is off by default")
        XCTAssertEqual(ThemeOpacitySettings.default.heroFade, 100)

        var settings = ThemeOpacitySettings.default
        settings.setBackgroundStrength(60, for: .black)
        settings.setBackgroundStrength(80, for: .light)
        settings.artworkBehindPage = 40
        settings.heroFade = 30
        primary.saveOpacity(settings)
        XCTAssertEqual(primary.loadOpacity(), settings)
        XCTAssertEqual(other.loadOpacity(), .default, "Profiles keep their own values")
        XCTAssertEqual(primary.loadOpacity().backgroundStrength(for: .dark), 100, "Each mode keeps its own strength")

        let snapshot = ProfileSettingsTransfer.capture(namespace: nil, defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "other", defaults: defaults)
        XCTAssertEqual(other.loadOpacity(), settings, "Travels with the profile-settings transfer")
    }

    func testOpacityResolvesSystemToTheDevicePageColourAndClampsValues() throws {
        XCTAssertEqual(ThemeOpacitySettings.Mode.resolved(.pureBlack, systemIsDark: false), .black)
        XCTAssertEqual(ThemeOpacitySettings.Mode.resolved(.system, systemIsDark: true), .dark)
        XCTAssertEqual(ThemeOpacitySettings.Mode.resolved(.system, systemIsDark: false), .light)
        XCTAssertEqual(ThemeOpacitySettings.backgroundStrengthOptions, [50, 60, 70, 80, 90, 100])
        let json = #"{"blackBackgroundStrength":10,"artworkBehindPage":-5,"heroFade":134}"#
        let decoded = try JSONDecoder().decode(ThemeOpacitySettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.blackBackgroundStrength, 50, "Never softer than 50%")
        XCTAssertEqual(decoded.artworkBehindPage, 0)
        XCTAssertEqual(decoded.heroFade, 100)
        XCTAssertEqual(decoded.lightBackgroundStrength, 100, "Missing fields keep their defaults")
    }

    @MainActor
    func testModelPersistsOnChange() {
        let defaults = makeDefaults()
        let model = ThemeSettingsModel(store: ThemeSettingsStore(defaults: defaults))
        XCTAssertEqual(model.theme, .default)
        // Anything but the default, so the assertion cannot pass by accident if
        // the default moves again.
        model.theme = .light
        XCTAssertEqual(ThemeSettingsStore(defaults: defaults).load(), .light)
    }

    func testCodableRoundTrip() throws {
        for theme in AppTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: data), theme)
        }
    }

    func testPickerOrderCoversEveryThemeCase() {
        // The pickers iterate `pickerOrder`, not `allCases`, so a new case added to
        // the enum but forgotten in `pickerOrder` would be silently unselectable.
        XCTAssertEqual(Set(AppTheme.pickerOrder), Set(AppTheme.allCases))
        XCTAssertEqual(AppTheme.pickerOrder.count, AppTheme.allCases.count)
        XCTAssertEqual(Set(MusicPlayerAppearance.pickerOrder), Set(MusicPlayerAppearance.allCases))
        XCTAssertEqual(MusicPlayerAppearance.pickerOrder.count, MusicPlayerAppearance.allCases.count)
    }
}

#if canImport(SwiftUI)
import SwiftUI
import CoreUI

final class ThemePaletteResolutionTests: XCTestCase {
    func testEveryThemeResolvesAPalette() {
        for theme in AppTheme.allCases {
            let dark = ThemePalette.palette(for: theme, systemColorScheme: .dark)
            let light = ThemePalette.palette(for: theme, systemColorScheme: .light)
            // `.system` follows the device scheme; the rest ignore it.
            if theme == .system {
                XCTAssertEqual(dark, .dark)
                XCTAssertEqual(light, .light)
            } else {
                XCTAssertEqual(dark, light, "\(theme) should not depend on the system scheme")
            }
        }
    }

    func testPureBlackHasNoGlowOthersAreThemed() {
        XCTAssertNil(ThemePalette.pureBlack.topGlow)
        XCTAssertNotNil(ThemePalette.dark.topGlow)
        XCTAssertNotNil(ThemePalette.light.topGlow)
    }
}
#endif
