import AppKit
import ClaudeUsageBarCore
import ServiceManagement
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
