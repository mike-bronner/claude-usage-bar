import ClaudeUsageBarCore
import Foundation
import Observation

/// UI state for every discovered account, refreshed on a timer. The only mutable state in the app.
@MainActor
@Observable
final class UsageModel {
    enum Condition: Equatable {
        case loading
        case live
        /// Token expired; `snapshot` holds whatever was last seen, if anything.
        case idle(since: Date)
        /// The usage endpoint throttled us; no request goes out for this account until `until`.
        case rateLimited(until: Date)
        case failed(String)
    }

    struct Status: Equatable {
        var plan: String?
        var snapshot: UsageSnapshot?
        var condition: Condition = .loading

        var isIdle: Bool { if case .idle = condition { true } else { false } }
    }

    typealias Scan = @Sendable () throws -> [Account]
    typealias Fetch = @Sendable (Account) async throws -> AccountUsage

    static let selectedAccountKey = "selectedAccountID"
    /// The usage endpoint rate-limits over a long, per-IP-ish window (≈180 requests/hour tripped
    /// it and stayed tripped); the session bucket is 5 h and the weekly ones 7 d, so 15 min loses
    /// nothing.
    static let pollInterval: Duration = .seconds(900)
    /// Backoff after a 429 with no usable `Retry-After` — one poll interval.
    static let defaultBackoff: TimeInterval = 900
    /// Opening the panel refreshes only when the numbers are older than this.
    static let staleAfter: TimeInterval = 30

    private(set) var accounts: [Account] = []
    private(set) var statuses: [Account.ID: Status] = [:]
    private(set) var lastRefresh: Date?
    private var retryNotBefore: [Account.ID: Date] = [:]

    /// The account whose details the menu shows. Persisted so it survives relaunch.
    var selectedID: Account.ID? {
        didSet { defaults.set(selectedID, forKey: Self.selectedAccountKey) }
    }

    private let scan: Scan
    private let fetch: Fetch
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    init(
        scan: @escaping Scan = { try AccountScanner().scan() },
        fetch: @escaping Fetch = { try await AccountUsageProvider().fetch(for: $0) },
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.scan = scan
        self.fetch = fetch
        self.defaults = defaults
        self.now = now
        selectedID = defaults.string(forKey: Self.selectedAccountKey)
    }

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedID } ?? accounts.first
    }

    /// One account's level: its icon color and its picker dot. Idleness, throttling, and failure
    /// all keep the last numbers, so they keep their level too: a failure can be a transient
    /// locked Keychain or no network after wake, and greying out a spent account would be a calm
    /// lie. Only with no limit still open does it read unknown, or idle for an idle account.
    func level(for account: Account) -> StatusLevel {
        guard let status = statuses[account.id] else { return .unknown }
        return StatusLevel.classify(snapshot: status.snapshot, idle: status.isIdle, now: now())
    }

    /// The account with the least allowance left, which the menu bar icon reflects whatever the
    /// picker shows. Within one level the higher tightest open limit wins (on credits, the level
    /// already ranks by credit used); only on a true tie does the earlier account win.
    var iconAccount: Account? {
        accounts.max { urgency(of: $0) < urgency(of: $1) }
    }

    private func urgency(of account: Account) -> (StatusLevel, Double) {
        let tightest = statuses[account.id]?.snapshot?.openLimits(at: now()).map(\.percent).max() ?? 0
        return (level(for: account), tightest)
    }

    /// The earliest reset still ahead across every account: when the icon must be re-evaluated
    /// without new data, because a limit's window closes.
    var nextReset: Date? {
        statuses.values.compactMap { $0.snapshot?.nextReset(after: now()) }.min()
    }

    /// The menu bar icon's level: that of `iconAccount`.
    var statusLevel: StatusLevel {
        iconAccount.map(level(for:)) ?? .unknown
    }

    /// Rescans accounts, then fetches all of them concurrently. Never throws: every failure lands
    /// in that account's status.
    func refreshAll() async {
        do {
            accounts = try scan()
        } catch {
            accounts = []
        }
        if selectedAccount?.id != selectedID { selectedID = selectedAccount?.id }

        let fetch = fetch
        let started = now()
        let due = accounts.filter { (retryNotBefore[$0.id] ?? .distantPast) <= started }
        let results = await withTaskGroup(of: (Account.ID, Result<AccountUsage, any Error>).self) { group in
            for account in due {
                group.addTask { (account.id, await Result { try await fetch(account) }) }
            }
            var collected: [Account.ID: Result<AccountUsage, any Error>] = [:]
            for await (id, result) in group { collected[id] = result }
            return collected
        }

        for account in due {
            var status = statuses[account.id] ?? Status()
            apply(results[account.id], to: &status, for: account.id, at: now())
            statuses[account.id] = status
        }
        statuses = statuses.filter { id, _ in accounts.contains { $0.id == id } }
        lastRefresh = now()
    }

    /// Refreshes only when the numbers are older than `staleAfter` — the panel opening must not
    /// add a request on top of the poller.
    func refreshIfStale() async {
        if let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.staleAfter { return }
        await refreshAll()
    }

    /// Keeps the previous snapshot through idle, throttling, and failure so the panel can dim it
    /// instead of going blank.
    private func apply(_ result: Result<AccountUsage, any Error>?, to status: inout Status, for id: Account.ID, at time: Date) {
        switch result {
        case .success(let usage):
            status.plan = usage.planLabel
            switch usage.state {
            case .live(let raw):
                do {
                    status.snapshot = try UsageSnapshot.decode(raw, fetchedAt: time)
                    status.condition = .live
                } catch {
                    status.condition = .failed("unreadable usage response")
                }
            case .idle(let expiredAt):
                status.condition = .idle(since: expiredAt)
            }
        case .failure(UsageError.rateLimited(let retryAfter)):
            let until = time.addingTimeInterval(retryAfter ?? Self.defaultBackoff)
            retryNotBefore[id] = until
            status.condition = .rateLimited(until: until)
        case .failure(let error):
            status.condition = .failed(Self.describe(error))
        case nil:
            status.condition = .failed("no result")
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case KeychainError.notFound: "no Keychain entry"
        case KeychainError.unreadable(let status): "Keychain error \(status)"
        case KeychainError.malformedPayload: "unreadable Keychain entry"
        case UsageError.unauthorized: "token rejected"
        case UsageError.rateLimited: "rate limited"
        case UsageError.unexpectedStatus(let code): "HTTP \(code)"
        case UsageError.malformedResponse: "unreadable usage response"
        case UsageError.transport: "network error"
        default: "\(error)"
        }
    }

    /// Refreshes immediately, then every `interval` until cancelled.
    func startPolling(every interval: Duration = pollInterval) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: interval)
            }
        }
    }
}

private extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
