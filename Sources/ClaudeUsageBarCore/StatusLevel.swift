import Foundation

/// What the menu bar icon says about one account. `Comparable` orders by how close the account is
/// to being blocked, so the worst of several accounts is simply their `max()`.
public enum StatusLevel: Sendable, Equatable, Comparable {
    /// Token expired and no limit with a live window is known.
    case idle
    /// No limit with an open window is known (loading, or a failure with nothing kept).
    case unknown
    case low
    case medium
    case high
    case critical
    /// A plan limit is spent and usage credits carry the account; `creditPercent` of them is used.
    case onCredits(creditPercent: Double)
    /// A plan limit is spent and no credits are left to carry the account.
    case out

    /// Percent thresholds, upper bounds exclusive: below 50 low, 75 medium, 90 high.
    static let mediumFrom = 50.0
    static let highFrom = 75.0
    static let criticalFrom = 90.0
    /// A limit at or past this is spent.
    static let spentFrom = 100.0

    /// The account's level from its tightest limit whose window is still open at `now`.
    ///
    /// Session, weekly, and per-model weekly limits all count: a spent weekly limit blocks Claude
    /// Code as hard as a spent session. A limit whose reset has passed says nothing about now, so
    /// it is ignored. An idle account keeps counting with its last-known numbers — hiding them
    /// would let a nearly spent account look calm — and reads as idle only when none are left.
    public static func classify(snapshot: UsageSnapshot?, idle: Bool, now: Date) -> StatusLevel {
        let open = snapshot?.openLimits(at: now) ?? []
        guard !open.isEmpty else { return idle ? .idle : .unknown }
        if open.contains(where: { $0.percent >= spentFrom }) {
            guard let credits = snapshot?.credits, credits.enabled, credits.percent < spentFrom else { return .out }
            return .onCredits(creditPercent: credits.percent)
        }
        return open.map { classify(percent: $0.percent, severity: $0.severity) }.max()!
    }

    /// One limit's level. The server's `severity` wins whenever it is not "normal"; otherwise the
    /// percent decides. An unfamiliar severity reads as critical — better a false alarm than a
    /// calm lie.
    public static func classify(percent: Double, severity: String?) -> StatusLevel {
        switch severity {
        case nil, "normal": byPercent(percent)
        case "warning": max(.high, byPercent(percent))
        default: .critical
        }
    }

    static func byPercent(_ percent: Double) -> StatusLevel {
        switch percent {
        case ..<mediumFrom: .low
        case ..<highFrom: .medium
        case ..<criticalFrom: .high
        default: .critical
        }
    }

    /// Worst first: out, on credits (more used is worse), critical, high, medium, low, unknown, idle.
    /// Unknown sits above idle only so the order stays total; both lose to any account with numbers.
    public static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: (Int, Double) {
        switch self {
        case .idle: (0, 0)
        case .unknown: (0, 1)
        case .low: (1, 0)
        case .medium: (2, 0)
        case .high: (3, 0)
        case .critical: (4, 0)
        case .onCredits(let percent): (5, percent)
        case .out: (6, 0)
        }
    }
}
