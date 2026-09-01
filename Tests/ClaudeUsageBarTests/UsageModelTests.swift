import XCTest
@testable import ClaudeUsageBar
@testable import ClaudeUsageBarCore

@MainActor
final class UsageModelTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suite: String!

    override func setUp() {
        suite = "UsageModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(
        accounts: [Account] = [personal, work],
        fetch: @escaping UsageModel.Fetch = liveUsage
    ) -> UsageModel {
        UsageModel(scan: { accounts }, fetch: fetch, defaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    func testRefreshPopulatesEveryAccount() async {
        let model = model()
        await model.refreshAll()

        XCTAssertEqual(model.accounts, [personal, work])
        XCTAssertEqual(model.statuses[personal.id]?.condition, .live)
        XCTAssertEqual(model.statuses[work.id]?.condition, .live)
        XCTAssertEqual(model.statuses[personal.id]?.plan, "Max (20x)")
        XCTAssertEqual(model.statuses[personal.id]?.snapshot?.session?.percent, 23)
        XCTAssertNotNil(model.lastRefresh)
    }

    func testDefaultsToFirstAccountAndPersistsSelection() async {
        let model = model()
        await model.refreshAll()
        XCTAssertEqual(model.selectedAccount, personal)
        XCTAssertEqual(model.statusLevel, .low)

        model.selectedID = work.id
        XCTAssertEqual(model.selectedAccount, work)
        XCTAssertEqual(defaults.string(forKey: UsageModel.selectedAccountKey), work.id)

        let relaunched = self.model()
        await relaunched.refreshAll()
        XCTAssertEqual(relaunched.selectedAccount, work, "selection must survive relaunch")
    }

    func testStaleSelectionFallsBackToFirstAccount() async {
        defaults.set("/gone/.claude-old", forKey: UsageModel.selectedAccountKey)
        let model = model()
        await model.refreshAll()
        XCTAssertEqual(model.selectedAccount, personal)
        XCTAssertEqual(model.selectedID, personal.id)
    }

    func testIdleKeepsLastSnapshotAndMarksIcon() async {
        let flag = Flag()
        let expiredAt = Date(timeIntervalSince1970: 1_799_999_000)
        let model = model(accounts: [personal]) { account in
            if await flag.isSet {
                return AccountUsage(subscriptionType: "max", rateLimitTier: nil, state: .idle(expiredAt: expiredAt))
            }
            return liveUsage(account)
        }
        await model.refreshAll()
        await flag.set()
        await model.refreshAll()

        let status = model.statuses[personal.id]
        XCTAssertEqual(status?.condition, .idle(since: expiredAt))
        XCTAssertEqual(status?.snapshot?.session?.percent, 23, "idle must keep the last-known numbers")
        XCTAssertEqual(model.statusLevel, .idle)
    }

    func testFailureIsRecordedPerAccountWithoutThrowing() async {
        let model = model { account in
            if account == work { throw UsageError.unauthorized }
            return liveUsage(account)
        }
        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.condition, .live)
        XCTAssertEqual(model.statuses[work.id]?.condition, .failed("token rejected"))
    }

    func testUnreadableUsageIsAFailureNotACrash() async {
        let model = model(accounts: [personal]) { _ in
            AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .live(rawUsage: Data("nope".utf8)))
        }
        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.condition, .failed("unreadable usage response"))
        XCTAssertEqual(model.statusLevel, .unknown)
    }

    func testRateLimitBacksOffUntilRetryAfter() async {
        let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
        let calls = Counter()
        let model = UsageModel(scan: { [personal] }, fetch: { account in
            if await calls.increment() == 1 { throw UsageError.rateLimited(retryAfter: 30) }
            return liveUsage(account)
        }, defaults: defaults, now: { clock.value })

        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.condition, .rateLimited(until: clock.value.addingTimeInterval(30)))

        clock.value = clock.value.addingTimeInterval(29)
        await model.refreshAll()
        let callsWhileBackedOff = await calls.count
        XCTAssertEqual(callsWhileBackedOff, 1, "no request may go out before Retry-After elapses")
        XCTAssertEqual(model.statuses[personal.id]?.condition, .rateLimited(until: clock.value.addingTimeInterval(1)))

        clock.value = clock.value.addingTimeInterval(2)
        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.condition, .live)
    }

    func testRateLimitWithoutRetryAfterUsesDefaultBackoff() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let model = UsageModel(scan: { [personal] }, fetch: { _ in throw UsageError.rateLimited(retryAfter: nil) }, defaults: defaults, now: { start })
        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.condition, .rateLimited(until: start.addingTimeInterval(UsageModel.defaultBackoff)))
    }

    func testRateLimitKeepsLastNumbersAndTheirColor() async {
        let calls = Counter()
        let model = UsageModel(scan: { [personal] }, fetch: { account in
            if await calls.increment() == 2 { throw UsageError.rateLimited(retryAfter: 30) }
            return liveUsage(account)
        }, defaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await model.refreshAll()
        await model.refreshAll()
        XCTAssertEqual(model.statuses[personal.id]?.snapshot?.session?.percent, 23)
        XCTAssertEqual(model.statusLevel, .low)
    }

    func testRefreshIfStaleSkipsRecentRefresh() async {
        let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
        let calls = Counter()
        let model = UsageModel(scan: { [personal] }, fetch: { account in
            _ = await calls.increment()
            return liveUsage(account)
        }, defaults: defaults, now: { clock.value })

        await model.refreshIfStale()
        clock.value = clock.value.addingTimeInterval(UsageModel.staleAfter - 1)
        await model.refreshIfStale()
        let afterFresh = await calls.count
        XCTAssertEqual(afterFresh, 1, "a panel open within the stale window must not fetch")

        clock.value = clock.value.addingTimeInterval(2)
        await model.refreshIfStale()
        let afterStale = await calls.count
        XCTAssertEqual(afterStale, 2)
    }

    func testRemovedAccountIsDropped() async {
        let accounts = Box([personal, work])
        let model = UsageModel(scan: { accounts.value }, fetch: { liveUsage($0) }, defaults: defaults)
        await model.refreshAll()
        accounts.value = [personal]
        await model.refreshAll()
        XCTAssertEqual(model.accounts, [personal])
        XCTAssertNil(model.statuses[work.id])
    }
}

private let personal = Account(configDirectory: URL(filePath: "/tmp/.claude"), emailAddress: "me@x.com", organizationName: nil, accountUUID: "1")
private let work = Account(configDirectory: URL(filePath: "/tmp/.claude-work"), emailAddress: "me@work.com", organizationName: "Work", accountUUID: "2")

/// Every account answers live with a session/weekly pair and a Max (20x) plan.
private func liveUsage(_ account: Account) -> AccountUsage {
    AccountUsage(subscriptionType: "max", rateLimitTier: "default_claude_max_20x", state: .live(rawUsage: usageJSON))
}

private let usageJSON = Data(#"{"limits":[{"kind":"session","percent":23},{"kind":"weekly_all","percent":5}]}"#.utf8)

private actor Counter {
    private(set) var count = 0
    func increment() -> Int { count += 1; return count }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
