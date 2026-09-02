import AppKit

// An AppKit app: the status item and its menu are AppKit, SwiftUI lives inside one menu item.
// No SwiftUI `App` — its mandatory scene (even an empty Settings) opens a window on activation.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Until the bundle carries LSUIElement, keep the unbundled dev binary out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = StatusItemController(model: UsageModel())
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
