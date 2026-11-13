import Foundation
import Observation

/// Persists the selected `AppTheme` across launches in standard `UserDefaults`.
///
/// Theme and gradient preference use profile-scoped UserDefaults and participate
/// in the existing profile-settings transfer. There is no cross-app sharing.
public protocol ThemeSettingsStoring: Sendable {
    func load() -> AppTheme
    func save(_ theme: AppTheme)
    func loadGradientEnabled() -> Bool
    func saveGradientEnabled(_ enabled: Bool)
    func loadOpacity() -> ThemeOpacitySettings
    func saveOpacity(_ settings: ThemeOpacitySettings)
    func loadBrowseLayout() -> BrowseLayout
    func saveBrowseLayout(_ layout: BrowseLayout)
    func loadBrowsePopupDelay() -> Int
    func saveBrowsePopupDelay(_ seconds: Int)
}

public extension ThemeSettingsStoring {
    func loadOpacity() -> ThemeOpacitySettings { .default }
    func saveOpacity(_ settings: ThemeOpacitySettings) {}
    func loadBrowseLayout() -> BrowseLayout { .default }
    func saveBrowseLayout(_ layout: BrowseLayout) {}
    func loadBrowsePopupDelay() -> Int { BrowsePopupDelay.default }
    func saveBrowsePopupDelay(_ seconds: Int) {}
}

public final class ThemeSettingsStore: ThemeSettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let gradientKey: String
    private let opacityKey: String
    private let browseLayoutKey: String
    private let browsePopupDelayKey: String

    /// - Parameter namespace: per-profile scope. `nil` (the default/primary
    ///   profile) uses the legacy un-suffixed key; other profiles pass their
    ///   `Profile.id`.
    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        self.key = SettingsKey.scoped("com.plozz.appTheme", namespace: namespace)
        self.gradientKey = SettingsKey.scoped(Self.gradientStorageKey, namespace: namespace)
        self.opacityKey = SettingsKey.scoped(Self.opacityStorageKey, namespace: namespace)
        self.browseLayoutKey = SettingsKey.scoped(Self.browseLayoutStorageKey, namespace: namespace)
        self.browsePopupDelayKey = SettingsKey.scoped(Self.browsePopupDelayStorageKey, namespace: namespace)
    }

    public static let browsePopupDelayStorageKey = "com.plozz.browsePopupDelay"

    public func loadBrowsePopupDelay() -> Int {
        guard let stored = defaults.object(forKey: browsePopupDelayKey) as? Int else {
            return BrowsePopupDelay.default
        }
        return BrowsePopupDelay.snapped(stored)
    }

    public func saveBrowsePopupDelay(_ seconds: Int) {
        defaults.set(BrowsePopupDelay.snapped(seconds), forKey: browsePopupDelayKey)
    }

    public static let browseLayoutStorageKey = "com.plozz.browseLayout"

    public func loadBrowseLayout() -> BrowseLayout {
        defaults.string(forKey: browseLayoutKey).flatMap(BrowseLayout.init(rawValue:)) ?? .default
    }

    public func saveBrowseLayout(_ layout: BrowseLayout) {
        defaults.set(layout.rawValue, forKey: browseLayoutKey)
    }

    public static let opacityStorageKey = "com.plozz.themeOpacity"

    public func loadOpacity() -> ThemeOpacitySettings {
        guard let data = defaults.data(forKey: opacityKey),
              let settings = try? JSONDecoder().decode(ThemeOpacitySettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public func saveOpacity(_ settings: ThemeOpacitySettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: opacityKey)
        }
    }

    public static let gradientStorageKey = "com.plozz.gradientBackgrounds"
    public static let defaultGradientEnabled = true

    public func loadGradientEnabled() -> Bool {
        defaults.object(forKey: gradientKey) as? Bool ?? Self.defaultGradientEnabled
    }

    public func saveGradientEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: gradientKey)
    }

    public func load() -> AppTheme {
        guard let raw = defaults.string(forKey: key),
              let theme = AppTheme(rawValue: raw) else {
            return .default
        }
        return theme
    }

    public func save(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: key)
    }
}

/// Observable wrapper so SwiftUI settings screens can two-way bind and have the
/// chosen theme persisted + broadcast to the view tree. Mirrors
/// `CaptionSettingsModel`.
@MainActor
@Observable
public final class ThemeSettingsModel {
    public var theme: AppTheme {
        didSet { store.save(theme) }
    }
    public var gradientEnabled: Bool {
        didSet { store.saveGradientEnabled(gradientEnabled) }
    }
    /// Background strength, artwork-behind-page and hero fade (see
    /// ``ThemeOpacitySettings``).
    public var opacity: ThemeOpacitySettings {
        didSet { store.saveOpacity(opacity) }
    }
    /// How the Home "See all" screen lays out its titles (see ``BrowseLayout``).
    public var browseLayout: BrowseLayout {
        didSet { store.saveBrowseLayout(browseLayout) }
    }
    /// Seconds focus rests on a title before the See all pop-up appears (see
    /// ``BrowsePopupDelay``).
    public var browsePopupDelay: Int {
        didSet { store.saveBrowsePopupDelay(browsePopupDelay) }
    }

    /// The pop-up delay when the See all layout uses the pop-up, else `nil`.
    public var browseDetailPopupDelay: Int? {
        browseLayout == .gridWithPopup ? browsePopupDelay : nil
    }

    private let store: ThemeSettingsStoring

    public init(store: ThemeSettingsStoring = ThemeSettingsStore()) {
        self.store = store
        self.theme = store.load()
        self.gradientEnabled = store.loadGradientEnabled()
        self.opacity = store.loadOpacity()
        self.browseLayout = store.loadBrowseLayout()
        self.browsePopupDelay = store.loadBrowsePopupDelay()
    }
}
