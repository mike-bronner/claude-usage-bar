import AppKit
import SwiftUI

/// An `NSHostingView` that keeps its frame at the content's fitting size.
///
/// A menu item sizes itself from its view's frame, and `NSMenu` reflects frame changes while the
/// menu is open ("Changes to the view's frame during tracking are reflected immediately in the
/// menu"). Sizing once, when the menu opens, leaves the item at the height of whichever account
/// was selected then: switching to a shorter one strands the block in the middle of the old
/// height, and switching to a taller one clips it.
///
/// SwiftUI already marks the view as needing layout when the observed content changes, so
/// overriding `layout()` is enough — no `sizingOptions` or intrinsic-size plumbing required.
final class SelfSizingHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("never loaded from a nib") }

    override func layout() {
        super.layout()
        fitToContent()
    }

    /// Idempotent by necessity: writing the frame schedules another layout pass, so an
    /// unconditional write would loop. A zero height means SwiftUI has nothing laid out yet.
    func fitToContent() {
        let fitting = fittingSize
        guard fitting.height > 0, frame.size != fitting else { return }
        frame.size = fitting
    }
}
