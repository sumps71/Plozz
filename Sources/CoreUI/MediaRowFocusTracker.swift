import SwiftUI

/// Which Home row focus was last in, so a row scrolls back to its first card
/// only once another row takes focus.
///
/// A row's own cards losing focus is not enough: a card's long-press menu takes
/// focus too, and the row has to stay where it is underneath it. Focus moving to
/// something that isn't a row (the hero, the navigation bar) leaves the record
/// alone, so coming straight back finds the row as it was left.
@MainActor
@Observable
public final class MediaRowFocusTracker {
    public private(set) var focusedRow: ObjectIdentifier?

    public init() {}

    /// Records that focus is in `row`, a card or See all card of it.
    public func enter(_ row: ObjectIdentifier) {
        if focusedRow != row { focusedRow = row }
    }

    /// Whether `focusedRow` changing from `previous` to `current` took focus
    /// from `row` to another row.
    public nonisolated static func focusLeft(
        _ row: ObjectIdentifier, from previous: ObjectIdentifier?, to current: ObjectIdentifier?
    ) -> Bool {
        previous == row && current != nil && current != row
    }
}

public extension EnvironmentValues {
    /// Home rows scroll back to their first card once focus has moved to another
    /// row. `nil` outside Home and unless the profile turns it on.
    @Entry var mediaRowFocusTracker: MediaRowFocusTracker? = nil
}
