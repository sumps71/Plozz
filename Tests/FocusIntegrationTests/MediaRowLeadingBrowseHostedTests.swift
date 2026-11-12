#if os(tvOS)
import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import CoreUI

/// The leading "See all" card rests just out of sight: a browsable row opens
/// scrolled by exactly the card's slot and gap, so its first item sits where a
/// row without the card puts it.
@MainActor
final class MediaRowLeadingBrowseHostedTests: XCTestCase {
    func testBrowsableRowRestsScrolledPastTheLeadingSeeAllCard() async throws {
        let items = (0..<12).map { MediaItem(id: "\($0)", title: "Title \($0)", kind: .movie) }
        let controller = UIHostingController(rootView:
            VStack(spacing: 80) {
                MediaRowView(title: Text(verbatim: "Plain"), items: items, onSelect: { _ in })
                    .browsingRow(nil)
                MediaRowView(title: Text(verbatim: "Browsable"), items: items, onSelect: { _ in })
                    .browsingRow({})
            }
            .frame(width: 1920, height: 1080, alignment: .top)
            .ignoresSafeArea()
        )
        let window = try await host(controller)
        defer { close(window) }
        try await Task.sleep(for: .milliseconds(1500))
        window.layoutIfNeeded()

        let rails = horizontalScrollViews(in: window).sorted { $0.frame(in: window).minY < $1.frame(in: window).minY }
        XCTAssertEqual(rails.count, 2, "One horizontal rail per row")
        guard rails.count == 2 else { return }
        let plain = rails[0], browsable = rails[1]
        XCTAssertEqual(plain.contentOffset.x, 0, accuracy: 0.5, "A row with no See all starts at its leading edge")
        // The browsable row adds one slot before its first item and one after its
        // last, so half the extra width is the leading card's slot and gap.
        let leadingSlot = (browsable.contentSize.width - plain.contentSize.width) / 2
        XCTAssertGreaterThan(leadingSlot, 100, "Both See all cards are laid out")
        XCTAssertEqual(browsable.contentOffset.x, leadingSlot, accuracy: 1,
                       "The leading See all rests just out of sight with the first item under the title")
    }

    private func horizontalScrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width,
           scroll.contentSize.height <= scroll.bounds.height + 1 {
            found.append(scroll)
        }
        for subview in view.subviews { found += horizontalScrollViews(in: subview) }
        return found
    }

    private func host(_ controller: UIViewController) async throws -> UIWindow {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private extension UIView {
    func frame(in window: UIWindow) -> CGRect { convert(bounds, to: window) }
}
#endif
