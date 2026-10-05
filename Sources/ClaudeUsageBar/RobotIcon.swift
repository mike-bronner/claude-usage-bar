import AppKit
import ClaudeUsageBarCore

/// The menu bar glyph: the robot, colored and drawn by the status of the account with the least
/// allowance left.
///
/// Not a template image on purpose — the color *is* the information.
enum RobotIcon {
    static let size = NSSize(width: 18, height: 18)

    /// Also the picker dot's color. On credits, the tint runs from purple at none used to red at
    /// all used.
    static func color(for level: StatusLevel) -> NSColor {
        switch level {
        case .idle, .unknown: .systemGray
        case .low: .systemGreen
        case .medium: .systemYellow
        case .high: .systemOrange
        case .critical, .out: .systemRed
        case .onCredits(let percent): creditTint(min(max(percent, 0), 100) / 100)
        }
    }

    /// System purple mixed toward system red by `fraction`, in sRGB so both ends are exact.
    /// Resolved per appearance, like the system colors it mixes.
    private static func creditTint(_ fraction: CGFloat) -> NSColor {
        NSColor(name: nil) { _ in
            guard let purple = NSColor.systemPurple.usingColorSpace(.sRGB),
                  let red = NSColor.systemRed.usingColorSpace(.sRGB) else { return .systemRed }
            func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * fraction }
            return NSColor(srgbRed: mix(purple.redComponent, red.redComponent),
                           green: mix(purple.greenComponent, red.greenComponent),
                           blue: mix(purple.blueComponent, red.blueComponent), alpha: 1)
        }
    }

    static func style(for level: StatusLevel) -> RobotGlyph.Style {
        switch level {
        case .out: .slashed
        case .onCredits: .dollar
        default: .face
        }
    }

    /// What the level means, in words: the tooltip, VoiceOver, and the picker's labels.
    static func describe(_ level: StatusLevel) -> String {
        switch level {
        case .idle: "idle"
        case .unknown: "no usage data"
        case .low: "low usage"
        case .medium: "medium usage"
        case .high: "high usage"
        case .critical: "critical usage"
        case .onCredits(let percent): "on usage credits, \(Int(percent.rounded()))% used"
        case .out: "out of allowance"
        }
    }

    /// Names the account that drives the icon, since the icon no longer follows the picker.
    static func label(account: Account?, level: StatusLevel) -> String {
        guard let account else { return "Claude usage: no accounts" }
        return "Claude usage: \(account.displayName), \(describe(level))"
    }

    static func image(for level: StatusLevel, label: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            RobotGlyph.draw(in: rect, tint: color(for: level), dimmed: level == .idle, style: style(for: level))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = label
        return image
    }
}
