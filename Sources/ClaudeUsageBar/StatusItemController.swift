import AppKit
import ClaudeUsageBarCore
import SwiftUI

/// The menu bar item and its menu — a real `NSMenu`, as the HIG asks of a menu bar extra.
///
/// Standard items do the commands (refresh, quit); one custom item hosts the account picker and
/// the usage block, the way Battery and Wi-Fi show status a plain item cannot. The picker lives in
/// the custom view because a native item dismisses the menu when picked.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: UsageModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let usageView: NSHostingView<UsageMenuContent>
    private var poller: Task<Void, Never>?

    init(model: UsageModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        usageView = NSHostingView(rootView: UsageMenuContent(model: model))
        super.init()

        menu.delegate = self
        // Accounts are picked inside the custom view, so no item carries a checkmark.
        menu.showsStateColumn = false
        statusItem.menu = menu
        rebuildMenu()
        trackIcon()
        poller = model.startPolling()
    }

    /// Re-renders the icon whenever the observed status changes; re-arms itself each time.
    private func trackIcon() {
        withObservationTracking {
            statusItem.button?.image = RobotIcon.image(for: model.statusLevel)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackIcon() }
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        Task { await model.refreshIfStale() }
    }

    // MARK: Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        usageView.frame.size = usageView.fittingSize
        let usage = NSMenuItem()
        usage.view = usageView
        menu.addItem(usage)
        menu.addItem(.separator())

        if let refreshed = model.lastRefresh {
            menu.addItem(Self.disabledItem("Updated \(refreshed.formatted(date: .omitted, time: .shortened))"))
        }
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit Claude Usage Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private static func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refresh(_ sender: Any?) {
        Task { await model.refreshAll() }
    }
}
