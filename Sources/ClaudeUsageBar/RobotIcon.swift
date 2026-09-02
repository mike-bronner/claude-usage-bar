import AppKit
import ClaudeUsageBarCore

/// The menu bar glyph: the robot, colored by the selected account's status.
///
/// Not a template image on purpose — the color *is* the information.
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
        let image = NSImage(size: size, flipped: false) { rect in
            RobotGlyph.draw(in: rect, tint: color(for: level), dimmed: level == .idle)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Claude usage: \(level)"
        return image
    }
}
