import SwiftUI
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class SelfSizingHostingViewTests: XCTestCase {
    /// Fixed-height rows, so the ideal height is exactly `count * 20`.
    private struct Rows: View {
        let count: Int

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    Color.clear.frame(width: 100, height: 20)
                }
            }
        }
    }

    func testFitToContentAdoptsTheFittingSize() {
        let view = SelfSizingHostingView(rootView: Rows(count: 5))
        view.fitToContent()
        XCTAssertEqual(view.frame.height, 100, accuracy: 1)
    }

    /// The bug: the menu item kept the height of whichever account was selected when it opened.
    func testFrameFollowsContentDownwards() {
        let view = SelfSizingHostingView(rootView: Rows(count: 5))
        view.fitToContent()
        XCTAssertEqual(view.frame.height, 100, accuracy: 1)

        view.rootView = Rows(count: 2)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.height, 40, accuracy: 1, "shorter content must shrink the item, not float inside the old height")
    }

    func testFrameFollowsContentUpwards() {
        let view = SelfSizingHostingView(rootView: Rows(count: 2))
        view.fitToContent()

        view.rootView = Rows(count: 6)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.height, 120, accuracy: 1, "taller content must grow the item instead of being clipped")
    }

    @Observable
    fileprivate final class RowCount {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    private struct ObservedRows: View {
        let rows: RowCount

        var body: some View { Rows(count: rows.value) }
    }

    /// The real trigger: picking another account mutates the observed model in place, the root
    /// view is never replaced. Mirrors `UsageMenuContent` reading `UsageModel`.
    func testFrameFollowsObservableModelChanges() {
        let rows = RowCount(5)
        let view = SelfSizingHostingView(rootView: ObservedRows(rows: rows))
        view.fitToContent()
        XCTAssertEqual(view.frame.height, 100, accuracy: 1)

        rows.value = 2
        settle(view)
        XCTAssertEqual(view.frame.height, 40, accuracy: 1, "switching account must resize the item, not centre the shorter block")
    }

    /// SwiftUI applies an observed change on the next main-runloop pass, not synchronously.
    private func settle(_ view: NSView) {
        for _ in 0..<20 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            view.layoutSubtreeIfNeeded()
        }
    }

    /// `fitToContent` writes the frame, which re-enters `invalidateIntrinsicContentSize`; without
    /// the equality guard that recurses until the stack overflows.
    func testFitToContentIsIdempotent() {
        let view = SelfSizingHostingView(rootView: Rows(count: 3))
        view.fitToContent()
        let settled = view.frame.size
        view.fitToContent()
        view.fitToContent()
        XCTAssertEqual(view.frame.size, settled)
    }
}
