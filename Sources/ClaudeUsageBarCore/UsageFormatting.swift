import Foundation

/// Human-readable time until a reset: "42m", "2h 15m", "3d 4h", or "now" once it has passed.
public enum ResetFormatter {
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        guard seconds > 0 else { return "now" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        switch (days, hours, minutes) {
        case (1..., _, _): return "\(days)d \(hours % 24)h"
        case (_, 1..., _): return "\(hours)h \(minutes % 60)m"
        default: return "\(max(minutes, 1))m"
        }
    }
}

/// The plan label as the Claude UI shows it, e.g. "Max (20x)", from the Keychain payload.
public enum PlanLabel {
    public static func text(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        let name = subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
        guard let multiplier = Self.multiplier(in: rateLimitTier) else { return name }
        return "\(name) (\(multiplier))"
    }

    /// Pulls a trailing "<n>x" token out of a tier such as `default_claude_max_20x`.
    static func multiplier(in tier: String?) -> String? {
        guard let last = tier?.split(separator: "_").last, last.hasSuffix("x"),
              Int(last.dropLast()) != nil
        else { return nil }
        return String(last)
    }
}
