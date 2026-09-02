import AppKit

// An AppKit app: the status item and its menu are AppKit, SwiftUI lives inside one menu item.
// No SwiftUI `App` — its mandatory scene (even an empty Settings) opens a window on activation.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    static let keychainExplainedKey = "keychainExplained"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Until the bundle carries LSUIElement, keep the unbundled dev binary out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)
        explainKeychainPromptOnce()
        statusItem = StatusItemController(model: UsageModel())
    }

    /// The first read of Claude Code's Keychain entries triggers macOS's "wants to use your
    /// confidential information" dialog, password field included. Say why before it appears.
    private func explainKeychainPromptOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.keychainExplainedKey) else { return }
        let alert = NSAlert()
        alert.messageText = "Claude Usage Bar reads Claude Code's login from your Keychain"
        alert.informativeText = """
            macOS will now ask, once per account, whether Claude Usage Bar may use the item \
            "Claude Code-credentials" — that is the token Claude Code stored when you logged in.

            Choose "Always Allow" so you are not asked again. The token is used only to fetch your \
            usage from Anthropic; it is never written, logged, or shown, and never refreshed.
            """
        alert.addButton(withTitle: "Continue")
        NSApplication.shared.activate()
        alert.runModal()
        defaults.set(true, forKey: Self.keychainExplainedKey)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
