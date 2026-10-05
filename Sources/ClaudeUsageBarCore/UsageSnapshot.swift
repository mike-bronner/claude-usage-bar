import Foundation

/// A monetary amount as the usage endpoint reports it: minor units plus an exponent.
public struct Money: Sendable, Equatable {
    public let amountMinor: Int
    public let currency: String
    public let exponent: Int

    public init(amountMinor: Int, currency: String, exponent: Int) {
        self.amountMinor = amountMinor
        self.currency = currency
        self.exponent = exponent
    }

    public var amount: Decimal { Decimal(amountMinor) / pow(10, exponent) }
    public var formatted: String { amount.formatted(.currency(code: currency)) }
}

/// One entry of the `limits` array — the self-describing list the Claude UI renders.
public struct UsageLimit: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case session
        case weeklyAll
        case weeklyScoped
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "session": self = .session
            case "weekly_all": self = .weeklyAll
            case "weekly_scoped": self = .weeklyScoped
            default: self = .other(rawValue)
            }
        }
    }

    public let kind: Kind
    public let percent: Double
    public let resetsAt: Date?
    /// Model display name for scoped limits (e.g. "Fable"); nil for the all-models buckets.
    public let modelName: String?
    public let severity: String
    public let isActive: Bool

    public init(kind: Kind, percent: Double, resetsAt: Date?, modelName: String?, severity: String, isActive: Bool) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.modelName = modelName
        self.severity = severity
        self.isActive = isActive
    }

    public var id: String { "\(kind)/\(modelName ?? "")" }

    /// Anything the server does not call "normal" deserves a tint.
    public var isElevated: Bool { severity != "normal" }
}

/// The `spend` object: usage credits beyond the plan.
public struct UsageCredits: Sendable, Equatable {
    public let enabled: Bool
    public let percent: Double
    public let used: Money?
    public let limit: Money?
    public let balance: Money?
    public let autoReload: Bool?
    public let canPurchaseCredits: Bool
    public let disabledReason: String?
    public let severity: String?

    public init(
        enabled: Bool, percent: Double, used: Money?, limit: Money?, balance: Money?,
        autoReload: Bool?, canPurchaseCredits: Bool, disabledReason: String?, severity: String?
    ) {
        self.enabled = enabled
        self.percent = percent
        self.used = used
        self.limit = limit
        self.balance = balance
        self.autoReload = autoReload
        self.canPurchaseCredits = canPurchaseCredits
        self.disabledReason = disabledReason
        self.severity = severity
    }
}

/// Everything the UI shows for one account, decoded from `/api/oauth/usage`.
///
/// Only `limits` and `spend` are read. The flat sibling keys (`five_hour`, `seven_day`, …)
/// duplicate `limits`; the codename keys are unreleased buckets and effectively always null.
public struct UsageSnapshot: Sendable, Equatable {
    public let limits: [UsageLimit]
    public let credits: UsageCredits?
    public let fetchedAt: Date

    public init(limits: [UsageLimit], credits: UsageCredits?, fetchedAt: Date) {
        self.limits = limits
        self.credits = credits
        self.fetchedAt = fetchedAt
    }

    public var session: UsageLimit? { limits.first { $0.kind == .session } }
    public var weeklyAll: UsageLimit? { limits.first { $0.kind == .weeklyAll } }
    public var weeklyScoped: [UsageLimit] { limits.filter { $0.kind == .weeklyScoped } }

    /// The limits whose window is still open at `now`. A limit whose reset has passed says nothing
    /// about now; one with no reset yet has not started its window and still counts.
    public func openLimits(at now: Date) -> [UsageLimit] {
        limits.filter { $0.resetsAt.map { $0 > now } ?? true }
    }

    /// The earliest reset still ahead of `now`, when an open limit's window closes.
    public func nextReset(after now: Date) -> Date? {
        limits.compactMap(\.resetsAt).filter { $0 > now }.min()
    }

    public static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UsageError.malformedResponse
        }
        let limits = try payload.limits.map { dto in
            UsageLimit(
                kind: .init(rawValue: dto.kind),
                percent: dto.percent,
                resetsAt: try dto.resets_at.map(Self.date(from:)),
                modelName: dto.scope?.model?.display_name,
                severity: dto.severity ?? "normal",
                isActive: dto.is_active ?? false
            )
        }
        let credits = payload.spend.map { dto in
            UsageCredits(
                enabled: dto.enabled,
                percent: dto.percent ?? 0,
                used: dto.used?.money,
                limit: dto.limit?.money,
                balance: dto.balance?.money,
                autoReload: dto.auto_reload?.value,
                canPurchaseCredits: dto.can_purchase_credits ?? false,
                disabledReason: dto.disabled_reason,
                severity: dto.severity
            )
        }
        return UsageSnapshot(limits: limits, credits: credits, fetchedAt: fetchedAt)
    }

    /// Timestamps arrive as `2026-09-01T22:50:00.347301+00:00`; a present but unparseable one is
    /// a malformed response, not a missing reset.
    static func date(from string: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: string) ?? plain.date(from: string) else {
            throw UsageError.malformedResponse
        }
        return date
    }
}

// MARK: - Wire shape

private struct Payload: Decodable {
    let limits: [LimitDTO]
    let spend: SpendDTO?
}

private struct LimitDTO: Decodable {
    let kind: String
    let percent: Double
    let resets_at: String?
    let scope: ScopeDTO?
    let severity: String?
    let is_active: Bool?
}

private struct ScopeDTO: Decodable {
    let model: ModelDTO?
}

private struct ModelDTO: Decodable {
    let display_name: String?
}

private struct SpendDTO: Decodable {
    let enabled: Bool
    let percent: Double?
    let used: MoneyDTO?
    let limit: MoneyDTO?
    let balance: MoneyDTO?
    let auto_reload: LenientBool?
    let can_purchase_credits: Bool?
    let disabled_reason: String?
    let severity: String?
}

private struct MoneyDTO: Decodable {
    let amount_minor: Int
    let currency: String
    let exponent: Int

    var money: Money { Money(amountMinor: amount_minor, currency: currency, exponent: exponent) }
}

/// `auto_reload` has only been observed as null. It may be a bool or an object with an `enabled`
/// flag once credits are on; either decodes, anything else reads as unknown rather than failing
/// the whole snapshot.
private struct LenientBool: Decodable {
    let value: Bool?

    private struct Flag: Decodable { let enabled: Bool }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = (try? container.decode(Bool.self)) ?? (try? container.decode(Flag.self))?.enabled
    }
}
