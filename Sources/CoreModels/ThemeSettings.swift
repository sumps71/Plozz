import Foundation

/// User-selectable app appearance (pure data model).
///
/// Mirrors the `AppTheme` in my Strozz app for structural parity, but the chosen
/// theme is persisted **locally** (standard `UserDefaults`) — there is no App
/// Group or cross-app preference sharing. The concrete colours each theme paints
/// with live in `CoreUI` (`ThemePalette`), so this stays Foundation-only and the
/// Settings screen can edit it without importing SwiftUI.
public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follow the device's current light/dark appearance.
    case system
    /// A light theme.
    case light
    /// A soft, dark gray theme.
    case dark
    /// A near-black theme. The persisted raw value stays unchanged so existing
    /// installs retain their selection after the user-facing rename.
    case pureBlack = "oled"

    public var id: String { rawValue }

    public var displayName: LocalizedStringResource {
        switch self {
        case .system:
            return LocalizedStringResource(
                "theme.appearance.system",
                defaultValue: "System",
                comment: "Appearance/theme option shown in the Settings theme picker."
            )
        case .light:
            return LocalizedStringResource(
                "theme.appearance.light",
                defaultValue: "Light",
                comment: "Appearance/theme option shown in the Settings theme picker."
            )
        case .dark:
            return LocalizedStringResource(
                "theme.appearance.dark",
                defaultValue: "Dark",
                comment: "Appearance/theme option shown in the Settings theme picker."
            )
        case .pureBlack:
            return LocalizedStringResource(
                "theme.appearance.pureBlack",
                defaultValue: "Black",
                comment: "Appearance/theme option shown in the Settings theme picker."
            )
        }
    }

    /// SF Symbol shown next to the option in Settings.
    public var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .pureBlack: return "moon.stars.fill"
        }
    }

    /// Fresh installs default to Black, regardless of the device appearance.
    ///
    /// Black rather than Dark because a media app is watched in the dark on a
    /// panel whose black pixels are genuinely off — an OLED TV, an OLED phone —
    /// so the chrome disappears and the artwork is the only thing lit. Dark grey
    /// reads as a box around the picture on exactly the displays this app is
    /// used on most. Users can still pick any look during onboarding or later
    /// in Settings.
    ///
    /// Only affects fresh installs: an existing install has its choice
    /// persisted under `com.plozz.appTheme` and keeps it.
    public static let `default`: AppTheme = .pureBlack

    /// The order the theme pickers (onboarding + Settings) present options in:
    /// Black first (the default), then Dark, Light, and System last.
    public static let pickerOrder: [AppTheme] = [.pureBlack, .dark, .light, .system]
}

/// How the Home "See all" screen lays out its titles (Apple TV).
public enum BrowseLayout: String, CaseIterable, Codable, Sendable {
    /// The full poster grid.
    case grid
    /// A slightly narrower grid beside an information panel for the focused
    /// title: artwork, details, ratings, synopsis and credits. Information only;
    /// the panel never takes focus.
    case gridWithDetails

    public static let `default`: BrowseLayout = .grid

    public var displayName: LocalizedStringResource {
        switch self {
        case .grid:
            return LocalizedStringResource(
                "browseLayout.grid",
                defaultValue: "Grid",
                comment: "See all screen layout option in Settings > Appearance: the full poster grid."
            )
        case .gridWithDetails:
            return LocalizedStringResource(
                "browseLayout.gridWithDetails",
                defaultValue: "Grid with details",
                comment: "See all screen layout option in Settings > Appearance: a poster grid beside a panel describing the focused title."
            )
        }
    }
}

/// Per-profile strength adjustments for the theme's page background and the
/// Home hero artwork. Every value defaults to today's look.
///
/// - Background strength: how strongly the page is tinted with the theme colour,
///   kept separately for Black, Dark and Light. Lower values blend the colour
///   toward a neutral grey (Black becomes charcoal, Light a greyer white).
/// - Artwork behind page: how much of the current hero artwork shows, blurred,
///   through the page behind the hero and rows. 0 (the default) is off.
/// - Hero fade: how far the hero artwork fades into the page. Lower values keep
///   more of the picture visible where it would normally melt away.
public struct ThemeOpacitySettings: Codable, Equatable, Sendable {
    /// The three page colours a theme can resolve to. System follows the device.
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case black, dark, light

        public static func resolved(_ theme: AppTheme, systemIsDark: Bool) -> Mode {
            switch theme {
            case .pureBlack: return .black
            case .dark: return .dark
            case .light: return .light
            case .system: return systemIsDark ? .dark : .light
            }
        }
    }

    public var blackBackgroundStrength: Int
    public var darkBackgroundStrength: Int
    public var lightBackgroundStrength: Int
    public var artworkBehindPage: Int
    public var heroFade: Int

    /// Background strength runs 0–100% in 10% steps. At 0% every mode's page is
    /// the same mid-grey and text keeps the theme's own colours, so contrast is
    /// lowest there (white text on grey for Black and Dark).
    public static let backgroundStrengthOptions: [Int] = Array(stride(from: 0, through: 100, by: 10))
    public static let percentOptions: [Int] = Array(stride(from: 0, through: 100, by: 10))

    public static let `default` = ThemeOpacitySettings()

    public init(
        blackBackgroundStrength: Int = 100,
        darkBackgroundStrength: Int = 100,
        lightBackgroundStrength: Int = 100,
        artworkBehindPage: Int = 0,
        heroFade: Int = 100
    ) {
        self.blackBackgroundStrength = Self.snap(blackBackgroundStrength, minimum: 0)
        self.darkBackgroundStrength = Self.snap(darkBackgroundStrength, minimum: 0)
        self.lightBackgroundStrength = Self.snap(lightBackgroundStrength, minimum: 0)
        self.artworkBehindPage = Self.snap(artworkBehindPage, minimum: 0)
        self.heroFade = Self.snap(heroFade, minimum: 0)
    }

    public func backgroundStrength(for mode: Mode) -> Int {
        switch mode {
        case .black: blackBackgroundStrength
        case .dark: darkBackgroundStrength
        case .light: lightBackgroundStrength
        }
    }

    public mutating func setBackgroundStrength(_ value: Int, for mode: Mode) {
        let value = Self.snap(value, minimum: 0)
        switch mode {
        case .black: blackBackgroundStrength = value
        case .dark: darkBackgroundStrength = value
        case .light: lightBackgroundStrength = value
        }
    }

    /// Snaps onto 10% steps within `minimum…100`.
    static func snap(_ value: Int, minimum: Int) -> Int {
        Int((Double(min(max(value, minimum), 100)) / 10).rounded()) * 10
    }

    private enum CodingKeys: String, CodingKey {
        case blackBackgroundStrength, darkBackgroundStrength, lightBackgroundStrength
        case artworkBehindPage, heroFade
    }

    /// Lenient: a missing or unreadable field falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallback: Int) -> Int {
            (try? c.decodeIfPresent(Int.self, forKey: key)) ?? fallback
        }
        self.init(
            blackBackgroundStrength: value(.blackBackgroundStrength, 100),
            darkBackgroundStrength: value(.darkBackgroundStrength, 100),
            lightBackgroundStrength: value(.lightBackgroundStrength, 100),
            artworkBehindPage: value(.artworkBehindPage, 0),
            heroFade: value(.heroFade, 100)
        )
    }
}

/// How the full-screen music player paints its background and text. Independent
/// of `AppTheme`: the player can follow the app theme or be pinned to one of its
/// own looks, because its immersive, artwork-tinted background reads differently
/// from the browsing chrome. Persisted per profile by `MusicPlayerSettingsStore`.
public enum MusicPlayerAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follow both the app theme and its gradient preference.
    case matchTheme
    /// Always a plain light background.
    case light
    /// Keep the former colorful Dark preference as Artwork on existing installs.
    case artwork = "dark"
    /// Always a plain dark background, distinct from the legacy colorful look.
    case dark = "neutralDark"
    /// Always true black. The persisted raw value stays unchanged.
    case pureBlack = "oled"

    public var id: String { rawValue }

    public var displayName: LocalizedStringResource {
        switch self {
        case .matchTheme:
            return LocalizedStringResource(
                "musicPlayerAppearance.matchAppTheme",
                defaultValue: "Match App Theme",
                comment: "Follow Plozz's app theme and Gradient Backgrounds preference, including their defaults."
            )
        case .light:
            return LocalizedStringResource(
                "musicPlayerAppearance.light",
                defaultValue: "Light",
                comment: "Music player appearance option in Settings."
            )
        case .dark:
            return LocalizedStringResource(
                "musicPlayerAppearance.dark",
                defaultValue: "Dark",
                comment: "Music player appearance option in Settings."
            )
        case .artwork:
            return LocalizedStringResource(
                "musicPlayerAppearance.artwork",
                defaultValue: "Artwork",
                comment: "Music player background sampled from the album artwork."
            )
        case .pureBlack:
            return LocalizedStringResource(
                "musicPlayerAppearance.black",
                defaultValue: "Black",
                comment: "Music player appearance option in Settings."
            )
        }
    }

    /// SF Symbol shown next to the option in Settings.
    public var symbolName: String {
        switch self {
        case .matchTheme: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .artwork: return "photo"
        case .pureBlack: return "moon.stars.fill"
        }
    }

    public static let `default`: MusicPlayerAppearance = .matchTheme

    public static let pickerOrder: [MusicPlayerAppearance] = [.matchTheme, .artwork, .pureBlack, .dark, .light]

    /// Base key scoped by the profile's music settings store.
    public static let storageKey = "musicPlayerAppearance"
}

/// Persistence for the Now Playing lyrics on/off toggle. Held here so every site
/// that reads the preference — the player's `@AppStorage` toggle and the lyrics
/// resolver that decides whether to consult the third-party LRCLIB fallback —
/// shares one key and default instead of duplicating a string literal.
public enum MusicLyricsPreference {
    /// AppStorage/UserDefaults key for whether the lyrics panel is enabled.
    public static let storageKey = "musicLyricsEnabled"
    /// Lyrics are on by default.
    public static let defaultEnabled = true
}

/// User control over the translucent "liquid glass" surfaces (cards, menus,
/// overlays). A tri-state because the app sits on top of the tvOS Accessibility
/// "Reduce Transparency" setting: the user can follow the system, force glass
/// on, or force solid surfaces. A **per-profile** display preference (each
/// profile keeps its own choice) like `AppTheme` / `CardStyle`: persisted via
/// `TransparencyPreferenceStore` (namespace-scoped) and rebuilt on profile
/// switch. Its `.system` option still defers to the device Accessibility setting,
/// so a viewer who needs reduced transparency system-wide always gets it.
public enum TransparencyPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Follow the tvOS Accessibility "Reduce Transparency" setting.
    case system
    /// Always show the translucent liquid-glass surfaces.
    case on
    /// Always use solid surfaces (reduced transparency).
    case off

    public var id: String { rawValue }

    public var displayName: LocalizedStringResource {
        switch self {
        case .system:
            return LocalizedStringResource(
                "transparency.system",
                defaultValue: "tvOS Default",
                comment: "Interface transparency option in Settings > Appearance."
            )
        case .on:
            return LocalizedStringResource(
                "transparency.on",
                defaultValue: "On",
                comment: "Interface transparency option in Settings > Appearance."
            )
        case .off:
            return LocalizedStringResource(
                "transparency.off",
                defaultValue: "Off",
                comment: "Interface transparency option in Settings > Appearance."
            )
        }
    }

    /// SF Symbol shown next to the option in Settings.
    public var symbolName: String {
        switch self {
        case .system: return "gearshape.fill"
        case .on: return "sparkles"
        case .off: return "square.fill"
        }
    }

    /// One-line explanation of what each option does, shown live under the
    /// tri-toggle as focus moves across it (mirrors `SkipIntrosMode.detail`).
    public var detail: LocalizedStringResource {
        switch self {
        case .system:
            return LocalizedStringResource(
                "transparency.detail.system",
                defaultValue: "Follow the tvOS “Reduce Transparency” accessibility setting.",
                comment: "One-line explanation shown under the transparency picker."
            )
        case .on:
            return LocalizedStringResource(
                "transparency.detail.on",
                defaultValue: "Always use translucent liquid-glass panels and cards.",
                comment: "One-line explanation shown under the transparency picker."
            )
        case .off:
            return LocalizedStringResource(
                "transparency.detail.off",
                defaultValue: "Always use solid backgrounds — no translucency.",
                comment: "One-line explanation shown under the transparency picker."
            )
        }
    }

    public static let `default`: TransparencyPreference = .system

    /// Persistence key base shared by RootView (reads the model to drive the
    /// environment) and Settings (writes it). Per-profile: the default profile
    /// reuses this un-suffixed key; other profiles namespace it via
    /// `SettingsKey.scoped`.
    public static let storageKey = "transparencyPreference"

    /// Whether liquid-glass surfaces should render SOLID (reduced transparency),
    /// resolving this preference against the current tvOS Accessibility setting.
    /// `on` forces glass even when the system asks to reduce it — an explicit,
    /// in-app override the user opted into.
    public func reducesTransparency(systemReduceTransparency: Bool) -> Bool {
        switch self {
        case .system: return systemReduceTransparency
        case .on: return false
        case .off: return true
        }
    }
}
