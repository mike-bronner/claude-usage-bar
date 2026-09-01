import AppKit
import ClaudeUsageBarCore

/// The menu bar glyph: a small robot whose color is the selected account's status.
///
/// Drawn in code so it has no asset catalog to bundle. Not a template image on purpose — the
/// color *is* the information.
enum RobotIcon {
    static let size = NSSize(width: 18, height: 18)

    static func color(for level: StatusLevel) -> NSColor {
        switch level {
        case .idle, .unknown: .systemGray
        case .low: .systemGreen
        case .medium: .systemYellow
        case .high: .systemOrange
        case .critical: .systemRed
        }
    }

    static func image(for level: StatusLevel) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(tint: color(for: level), dimmed: level == .idle)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Claude usage: \(level)"
        return image
    }

    /// Head with two eyes and a mouth punched out, ears, and an antenna. Coordinates are points
    /// in an 18×18 box, origin bottom-left.
    private static func draw(tint: NSColor, dimmed: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        tint.withAlphaComponent(dimmed ? 0.45 : 1).setFill()

        NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 12, height: 10.5), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 6, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
        NSBezierPath(roundedRect: NSRect(x: 15.5, y: 6, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
        NSBezierPath(rect: NSRect(x: 8.4, y: 13, width: 1.2, height: 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.75, y: 14.75, width: 2.5, height: 2.5)).fill()

        // Facial features are holes so they read on any menu bar background.
        context.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5.5, y: 7.5, width: 2.5, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 7.5, width: 2.5, height: 2.5)).fill()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 4.5, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
        context.setBlendMode(.normal)
    }
}
