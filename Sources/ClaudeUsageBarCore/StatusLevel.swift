import Foundation

/// What the menu bar icon's color says about the selected account.
public enum StatusLevel: Sendable, Equatable, CaseIterable {
    /// Token expired; Claude Code has not been used since.
    case idle
    /// No usable numbers (loading, or the last fetch failed).
    case unknown
    case low
    case medium
    case high
    case critical

    /// Session percent thresholds, upper bounds exclusive: below 50 low, 75 medium, 90 high.
    static let mediumFrom = 50.0
    static let highFrom = 75.0
    static let criticalFrom = 90.0

    /// The server's `severity` wins whenever it is not "normal"; otherwise the session percent
    /// decides. An unfamiliar severity reads as critical — better a false alarm than a calm lie.
    public static func classify(sessionPercent: Double?, severity: String?, idle: Bool) -> StatusLevel {
        if idle { return .idle }
        guard let sessionPercent else { return .unknown }
        switch severity {
        case nil, "normal": break
        case "warning": return max(.high, Self.byPercent(sessionPercent))
        default: return .critical
        }
        return Self.byPercent(sessionPercent)
    }

    static func byPercent(_ percent: Double) -> StatusLevel {
        switch percent {
        case ..<mediumFrom: .low
        case ..<highFrom: .medium
        case ..<criticalFrom: .high
        default: .critical
        }
    }

    private static func max(_ lhs: StatusLevel, _ rhs: StatusLevel) -> StatusLevel {
        let order = StatusLevel.allCases
        return order.firstIndex(of: lhs)! >= order.firstIndex(of: rhs)! ? lhs : rhs
    }
}
