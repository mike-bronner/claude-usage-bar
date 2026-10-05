import AppKit
import ClaudeUsageBarCore
import ServiceManagement
import SwiftUI

/// The menu bar item and its menu — a real `NSMenu`, as the HIG asks of a menu bar extra.
///
/// Standard items do the commands that may close the menu (quit, launch at login); one custom item
/// hosts the account picker, the usage block, and Refresh, the way Battery and Wi-Fi show status a
/// plain item cannot. Picker and Refresh live in the custom view because a native item dismisses
/// the menu when picked.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: UsageModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let usageView: SelfSizingHostingView<UsageMenuContent>
    private var poller: Task<Void, Never>?
    private var resetWake: Task<Void, Never>?

    init(model: UsageModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        usageView = SelfSizingHostingView(rootView: UsageMenuContent(model: model))
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        trackIcon()
        poller = model.startPolling()
    }

    /// Re-renders the icon whenever the observed status changes; re-arms itself each time.
    private func trackIcon() {
        withObservationTracking {
            renderIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackIcon() }
        }
    }

    /// Draws the icon. The tooltip and the image's accessibility description name the account
    /// driving it.
    ///
    /// The level also depends on the clock: a limit whose reset passes stops counting with no new
    /// data, and no observed state changes then. So each render arms a wake-up for the next reset,
    /// which re-renders from the numbers already held and sends no request.
    private func renderIcon() {
        let label = RobotIcon.label(account: model.iconAccount, level: model.statusLevel)
        statusItem.button?.image = RobotIcon.image(for: model.statusLevel, label: label)
        statusItem.button?.toolTip = label

        resetWake?.cancel()
        guard let reset = model.nextReset else { return }
        resetWake = Task { @MainActor [weak self] in
            // A second past the reset, so the limit is behind `now` when the level is recomputed.
            try? await Task.sleep(for: .seconds(max(reset.timeIntervalSinceNow, 0) + 1))
            guard !Task.isCancelled else { return }
            self?.renderIcon()
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
        usageView.fitToContent()
        let usage = NSMenuItem()
        usage.view = usageView
        menu.addItem(usage)
        menu.addItem(.separator())

        // The visible Refresh is a button in the custom view so the menu stays open; this hidden
        // item only gives ⌘R a home.
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isHidden = true
        menu.addItem(refresh)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
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

    /// Registers or unregisters the app as a login item. Only a bundled app can register; the
    /// unbundled dev binary gets the system's error, shown rather than swallowed.
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
