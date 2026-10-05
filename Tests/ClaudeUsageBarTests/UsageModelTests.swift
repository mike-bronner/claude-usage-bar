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

    func testIdleKeepsLastSnapshotAndItsLevel() async {
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
        XCTAssertEqual(model.statusLevel, .low, "an idle account counts with its last-known numbers")
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

    // MARK: Icon aggregation

    /// A model whose accounts answer with the given usage, or idle / a failure.
    private func model(_ answers: [Account: Answer]) -> UsageModel {
        model(accounts: [personal, work]) { account in
            switch answers[account] {
            case .live(let json): AccountUsage(subscriptionType: "max", rateLimitTier: nil, state: .live(rawUsage: Data(json.utf8)))
            case .idle: AccountUsage(subscriptionType: "max", rateLimitTier: nil, state: .idle(expiredAt: .distantPast))
            case .fail, nil: throw UsageError.unauthorized
            }
        }
    }

    func testIconFollowsTheAccountWithLeastLeftWhateverIsSelected() async {
        let model = model([personal: .live(session(23)), work: .live(weekly(95))])
        await model.refreshAll()
        XCTAssertEqual(model.selectedAccount, personal)
        XCTAssertEqual(model.iconAccount, work, "a weekly limit counts as hard as a session")
        XCTAssertEqual(model.statusLevel, .critical)

        model.selectedID = work.id
        model.selectedID = personal.id
        XCTAssertEqual(model.iconAccount, work, "the picker selection does not move the icon")
        XCTAssertEqual(model.level(for: personal), .low)
    }

    func testIdleAccountCountsWithLastKnownNumbers() async {
        let answers = Box<[Account: Answer]>([personal: .live(session(10)), work: .live(session(92))])
        let model = model(accounts: [personal, work]) { account in
            switch answers.value[account] {
            case .live(let json): AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .live(rawUsage: Data(json.utf8)))
            default: AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .idle(expiredAt: .distantPast))
            }
        }
        await model.refreshAll()
        answers.value[work] = .idle
        await model.refreshAll()
        XCTAssertTrue(model.statuses[work.id]?.isIdle == true)
        XCTAssertEqual(model.iconAccount, work)
        XCTAssertEqual(model.statusLevel, .critical)
    }

    func testIdleAccountWhoseResetPassedYieldsToAnyAccountWithNumbers() async {
        let answers = Box<[Account: Answer]>([personal: .live(session(10)), work: .live(session(100, resets: past))])
        let model = model(accounts: [personal, work]) { account in
            switch answers.value[account] {
            case .live(let json): AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .live(rawUsage: Data(json.utf8)))
            default: AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .idle(expiredAt: .distantPast))
            }
        }
        await model.refreshAll()
        answers.value[work] = .idle
        await model.refreshAll()
        XCTAssertEqual(model.level(for: work), .idle, "a stale 100% past its reset must not keep alarming")
        XCTAssertEqual(model.iconAccount, personal)
        XCTAssertEqual(model.statusLevel, .low)
    }

    func testAccountsWithoutNumbersCountOnlyWhenNoneHaveAny() async {
        let mixed = model([personal: .fail, work: .live(session(10))])
        await mixed.refreshAll()
        XCTAssertEqual(mixed.level(for: personal), .unknown)
        XCTAssertEqual(mixed.iconAccount, work)

        let none = model([personal: .idle, work: .fail])
        await none.refreshAll()
        XCTAssertEqual(none.iconAccount, work, "unknown outranks idle")
        XCTAssertEqual(none.statusLevel, .unknown)
    }

    func testFailedAccountKeepsRankingWithItsLastNumbers() async {
        let flag = Flag()
        let model = model(accounts: [personal, work]) { account in
            if account == work, await flag.isSet { throw UsageError.unauthorized }
            return AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .live(rawUsage: Data(session(account == work ? 95 : 10).utf8)))
        }
        await model.refreshAll()
        await flag.set()
        await model.refreshAll()
        XCTAssertEqual(model.statuses[work.id]?.condition, .failed("token rejected"))
        XCTAssertEqual(model.level(for: work), .critical, "a failure must not grey out a nearly spent account")
        XCTAssertEqual(model.iconAccount, work)
    }

    func testOutOutranksOnCreditsWhichOutranksCritical() async {
        let creditsVsCritical = model([personal: .live(weekly(99)), work: .live(session(100, credits: (true, 30)))])
        await creditsVsCritical.refreshAll()
        XCTAssertEqual(creditsVsCritical.iconAccount, work)
        XCTAssertEqual(creditsVsCritical.statusLevel, .onCredits(creditPercent: 30))

        let outVsCredits = model([personal: .live(session(100, credits: (true, 90))), work: .live(weekly(100, credits: (false, 0)))])
        await outVsCredits.refreshAll()
        XCTAssertEqual(outVsCredits.iconAccount, work)
        XCTAssertEqual(outVsCredits.statusLevel, .out)
    }

    func testMoreCreditUsedIsWorse() async {
        let model = model([personal: .live(session(100, credits: (true, 20))), work: .live(session(100, credits: (true, 70)))])
        await model.refreshAll()
        XCTAssertEqual(model.iconAccount, work)
    }

    func testWithinOneLevelTheAccountWithLessLeftWins() async {
        let model = model([personal: .live(session(60)), work: .live(weekly(70))])
        await model.refreshAll()
        XCTAssertEqual(model.level(for: personal), model.level(for: work))
        XCTAssertEqual(model.iconAccount, work)
    }

    func testTrueTieGoesToTheEarlierAccount() async {
        let model = model([personal: .live(session(60)), work: .live(session(60))])
        await model.refreshAll()
        XCTAssertEqual(model.iconAccount, personal)
    }

    func testPassedResetChangesTheLevelWithoutARefresh() async {
        let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
        let calls = Counter()
        let model = UsageModel(scan: { [personal, work] }, fetch: { account in
            _ = await calls.increment()
            let json = account == personal ? session(100, resets: soon) : weekly(30)
            return AccountUsage(subscriptionType: nil, rateLimitTier: nil, state: .live(rawUsage: Data(json.utf8)))
        }, defaults: defaults, now: { clock.value })
        await model.refreshAll()
        XCTAssertEqual(model.statusLevel, .out)
        XCTAssertEqual(model.nextReset, try? UsageSnapshot.date(from: soon), "the earliest reset across accounts")

        clock.value = try! UsageSnapshot.date(from: soon).addingTimeInterval(1)
        XCTAssertEqual(model.level(for: personal), .unknown, "the spent session reset; nothing else is open")
        XCTAssertEqual(model.iconAccount, work)
        XCTAssertEqual(model.statusLevel, .low)
        XCTAssertEqual(model.nextReset, try? UsageSnapshot.date(from: future), "the passed reset is no longer next")
        let fetches = await calls.count
        XCTAssertEqual(fetches, 2, "re-evaluating sends no request")
    }

    func testNoSnapshotMeansNoNextReset() async {
        let model = model([personal: .fail, work: .fail])
        await model.refreshAll()
        XCTAssertNil(model.nextReset)
    }

    func testNoAccountsIsUnknown() async {
        let model = model(accounts: [])
        await model.refreshAll()
        XCTAssertNil(model.iconAccount)
        XCTAssertEqual(model.statusLevel, .unknown)
        XCTAssertEqual(RobotIcon.label(account: nil, level: .unknown), "Claude usage: no accounts")
    }

    // MARK: Icon look

    func testCreditTintRunsFromPurpleToRed() throws {
        XCTAssertEqual(try rgb(RobotIcon.color(for: .onCredits(creditPercent: 0))), try rgb(.systemPurple))
        XCTAssertEqual(try rgb(RobotIcon.color(for: .onCredits(creditPercent: 100))), try rgb(.systemRed))
        let (purple, red) = (try rgb(.systemPurple), try rgb(.systemRed))
        let half = zip(purple, red).map { Int((Double($0 + $1) / 2).rounded()) }
        XCTAssertEqual(try rgb(RobotIcon.color(for: .onCredits(creditPercent: 50))), half)
        XCTAssertEqual(try rgb(RobotIcon.color(for: .onCredits(creditPercent: 150))), red, "past 100% stays red")
        XCTAssertEqual(try rgb(RobotIcon.color(for: .out)), try rgb(.systemRed), "an out account is plain red")
    }

    func testStyleMarksOutAndCredits() {
        XCTAssertEqual(RobotIcon.style(for: .out), .slashed)
        XCTAssertEqual(RobotIcon.style(for: .onCredits(creditPercent: 40)), .dollar)
        XCTAssertEqual(RobotIcon.style(for: .critical), .face)
        XCTAssertEqual(RobotIcon.style(for: .idle), .face)
    }

    func testLabelNamesTheAccountAndItsState() {
        XCTAssertEqual(RobotIcon.label(account: work, level: .onCredits(creditPercent: 42.4)), "Claude usage: Work, on usage credits, 42% used")
        XCTAssertEqual(RobotIcon.label(account: personal, level: .out), "Claude usage: me, out of allowance")
        XCTAssertEqual(RobotIcon.label(account: personal, level: .critical), "Claude usage: me, critical usage")
        XCTAssertEqual(RobotIcon.image(for: .out, label: "x").accessibilityDescription, "x")
    }

    private func rgb(_ color: NSColor) throws -> [Int] {
        let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
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

private enum Answer { case live(String), idle, fail }

/// The model's clock reads 2027-01-15T08:00Z; `soon` is an hour later, the others well either side.
private let future = "2030-01-01T00:00:00Z"
private let soon = "2027-01-15T09:00:00Z"
private let past = "2020-01-01T00:00:00Z"

private func session(_ percent: Double, resets: String = future, credits: (enabled: Bool, percent: Double)? = nil) -> String {
    usage(kind: "session", percent, resets: resets, credits: credits)
}

private func weekly(_ percent: Double, credits: (enabled: Bool, percent: Double)? = nil) -> String {
    usage(kind: "weekly_all", percent, resets: future, credits: credits)
}

private func usage(kind: String, _ percent: Double, resets: String, credits: (enabled: Bool, percent: Double)?) -> String {
    let spend = credits.map { #","spend":{"enabled":\#($0.enabled),"percent":\#($0.percent)}"# } ?? ""
    return #"{"limits":[{"kind":"\#(kind)","percent":\#(percent),"resets_at":"\#(resets)"}]\#(spend)}"#
}

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
