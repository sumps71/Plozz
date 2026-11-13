import CoreModels
import CoreUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Both shells supply their normal cards and navigation; membership and controls
/// are shared so a Home shelf means the same thing on either platform.
public struct HomeRowBrowseView<Card: View>: View {
    @Bindable private var model: HomeRowBrowseModel
    private let columns: [GridItem]
    private let card: (MediaItem) -> Card
    private let spoilerSettings: SpoilerSettings
    private let loadDetails: (@MainActor (MediaItem) async -> MediaItem?)?
    @Environment(\.locale) private var locale
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzNavigationContentInset) private var navigationInset
    @State private var moreRequest = 0
    #if os(tvOS)
    @Namespace private var entryFocusScope
    @State private var hasResolvedEntryFocus = false
    @Environment(\.browseShowsDetails) private var showsDetails
    @FocusState private var focusedItemID: String?
    @State private var detailItemID: String?
    @State private var detailedItems: [String: MediaItem] = [:]
    @State private var panelTrailingGap: CGFloat = 0

    private static var screenWidth: CGFloat { UIScreen.main.bounds.width }
    #endif
    private struct LoadKey: Equatable {
        let query: HomeRowBrowseQuery
        let snapshot: [MediaItem]?
    }

    /// - Parameters:
    ///   - spoilerSettings: hides episode titles and synopses in the details panel.
    ///   - loadDetails: fetches the full record for the focused title from its own
    ///     server, so the details panel can show its synopsis and credits.
    public init(
        model: HomeRowBrowseModel, columns: [GridItem],
        spoilerSettings: SpoilerSettings = .default,
        loadDetails: (@MainActor (MediaItem) async -> MediaItem?)? = nil,
        @ViewBuilder card: @escaping (MediaItem) -> Card
    ) {
        self.model = model
        self.columns = columns
        self.spoilerSettings = spoilerSettings
        self.loadDetails = loadDetails
        self.card = card
    }

    public var body: some View {
        #if os(tvOS)
        if showsDetails {
            HStack(spacing: HomeRowBrowseDetailPanel.gridGap) {
                grid
                // The slot keeps the grid's width fixed; the panel is drawn from
                // the slot's leading edge out to the screen's trailing edge, past
                // the safe area the slot stops at.
                Color.clear
                    .frame(width: HomeRowBrowseDetailPanel.width)
                    .frame(maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        max(0, Self.screenWidth - proxy.frame(in: .global).maxX)
                    } action: { panelTrailingGap = $0 }
                    .overlay(alignment: .topLeading) {
                        let width = HomeRowBrowseDetailPanel.width + panelTrailingGap
                        HomeRowBrowseDetailPanel(
                            item: detailItem, spoilerSettings: spoilerSettings, drawnWidth: width
                        )
                        .frame(width: width)
                        .ignoresSafeArea(edges: .vertical)
                    }
            }
            .onChange(of: focusedItemID) { _, id in
                if let id { detailItemID = id }
            }
            .task(id: detailItemID) { await loadDetailsForFocusedItem() }
        } else {
            grid
        }
        #else
        grid
        #endif
    }

    #if os(tvOS)
    /// The focused title, at its fullest known record.
    private var detailItem: MediaItem? {
        let id = detailItemID ?? model.items.first?.stablePresentationID
        guard let id else { return nil }
        return detailedItems[id] ?? model.items.first { $0.stablePresentationID == id }
    }

    /// Waits for focus to settle, then fetches the full record once per title.
    private func loadDetailsForFocusedItem() async {
        guard let id = detailItemID, detailedItems[id] == nil, let loadDetails,
              let item = model.items.first(where: { $0.stablePresentationID == id }) else { return }
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        guard let full = await loadDetails(item), !Task.isCancelled else { return }
        detailedItems[id] = item.mergingBrowseDetails(from: full)
    }
    #endif

    /// One column fewer when the details panel takes the right of the screen.
    private var gridColumns: [GridItem] {
        #if os(tvOS)
        if showsDetails, columns.count > 1 { return Array(columns.dropLast()) }
        #endif
        return columns
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                #if os(tvOS)
                HStack {
                    heading
                        .layoutPriority(1)
                    Spacer(minLength: PlozzTheme.Spacing.large)
                    BrowseQueryControls {
                        filterControl
                        sortControl.fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(awaitsGridEntry)
                }
                .lineLimit(1)
                .focusSection()
                #endif
                if model.query == model.appliedQuery {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: metrics.gridSpacing) {
                        ForEach(model.items, id: \.stablePresentationID) { item in
                            card(item)
                                #if os(tvOS)
                                .modifier(BrowseDetailFocusTracking(
                                    isEnabled: showsDetails, focus: $focusedItemID, id: item.stablePresentationID
                                ))
                                .disabled(!hasResolvedEntryFocus && item.stablePresentationID != model.items.first?.stablePresentationID)
                                .prefersDefaultFocus(
                                    !hasResolvedEntryFocus && item.stablePresentationID == model.items.first?.stablePresentationID,
                                    in: entryFocusScope
                                )
                                #endif
                                .onAppear {
                                    if item.stablePresentationID == model.items.last?.stablePresentationID,
                                       model.hasMore, !model.isLoading, model.error == nil {
                                        moreRequest += 1
                                    }
                                }
                        }
                    }
                    #if os(tvOS)
                    .background {
                        NativeFocusRegionObserver(isEnabled: !hasResolvedEntryFocus) { hasResolvedEntryFocus = true }
                    }
                    #endif
                }
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error.userMessage)
                        Button("Retry") { moreRequest += 1 }
                    }
                } else if model.isLoading || model.query != model.appliedQuery {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if model.hasMore {
                    Button("Load more") { moreRequest += 1 }
                        #if os(tvOS)
                        .disabled(awaitsGridEntry)
                        #endif
                        .onAppear { moreRequest += 1 }
                } else if model.items.isEmpty {
                    Text("No titles to show")
                        .plozzForeground(.secondary)
                }
            }
            .padding(.leading, horizontalPadding + navigationInset)
            .padding(.trailing, horizontalPadding)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("home-row-browser")
        .task(id: LoadKey(query: model.query, snapshot: model.liveSnapshot)) { await model.load() }
        .task(id: moreRequest) {
            guard moreRequest > 0, !model.isLoading else { return }
            await model.load()
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .mediaItemDidMutate) {
                if let mutation = MediaItemMutation.from(notification) { await model.applyMutation(mutation) }
            }
        }
        .onChange(of: model.scopeIsCurrent) { _, current in if !current { model.invalidate() } }
        #if os(tvOS)
        .focusScope(entryFocusScope)
        .background {
            NativeFocusRegionObserver(isEnabled: !hasResolvedEntryFocus && !awaitsGridEntry) {
                hasResolvedEntryFocus = true
            }
        }
        #endif
        #if os(iOS)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortControl.labelStyle(.iconOnly)
                filterControl.labelStyle(.iconOnly)
            }
        }
        #endif
    }

    #if os(tvOS)
    private var awaitsGridEntry: Bool {
        !hasResolvedEntryFocus && model.error == nil && (model.isLoading || model.hasMore || !model.items.isEmpty)
    }
    #endif

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        PlozzTheme.Metrics.screenPadding
        #else
        20
        #endif
    }

    private var title: Text {
        if let localized = model.localizedTitle {
            if let suffix = model.titleSuffix { return Text(localized) + Text(verbatim: suffix) }
            return Text(localized)
        }
        return Text(verbatim: model.title)
    }

    private var heading: some View {
        title.font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("home-row-browser-title")
    }

    private var sortControl: some View {
        Menu {
            HomeContentSortOptions(query: $model.query)
        } label: {
            Label {
                Text(model.query.sortTitle)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #endif
        }
        .accessibilityLabel(Text("Sort: \(model.query.sortTitle)"))
        .accessibilityIdentifier("home-row-sort-menu")
    }

    private var filterControl: some View {
        BrowseFilterMenu(
            activeCount: model.query.activeFilterCount,
            summary: model.query.filterSummary(in: locale)
        ) {
            HomeContentFilterOptions(query: $model.query)
        }
        .accessibilityIdentifier("home-row-filter-menu")
    }

}

extension MediaItem {
    /// Keeps the grid's own identity, source and watch state, and takes the
    /// descriptive fields the browse list may have left out.
    func mergingBrowseDetails(from full: MediaItem) -> MediaItem {
        var merged = self
        if merged.overview?.isEmpty != false { merged.overview = full.overview }
        if merged.genres.isEmpty { merged.genres = full.genres }
        if merged.people.isEmpty { merged.people = full.people }
        if merged.ratings.isEmpty { merged.ratings = full.ratings }
        merged.productionYear = merged.productionYear ?? full.productionYear
        merged.officialRating = merged.officialRating ?? full.officialRating
        merged.runtime = merged.runtime ?? full.runtime
        merged.backdropURL = merged.backdropURL ?? full.backdropURL
        return merged
    }
}

#if os(tvOS)
/// Reports the focused card to the details panel, and only while it is shown,
/// so the plain grid never re-renders on focus changes.
private struct BrowseDetailFocusTracking: ViewModifier {
    let isEnabled: Bool
    let focus: FocusState<String?>.Binding
    let id: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.focused(focus, equals: id)
        } else {
            content
        }
    }
}
#endif
