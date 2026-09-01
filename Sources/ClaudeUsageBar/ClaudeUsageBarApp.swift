import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The status item is AppKit; SwiftUI only needs a scene to exist.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Until the bundle carries LSUIElement, keep the unbundled dev binary out of the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = StatusItemController(model: UsageModel())
    }
}
