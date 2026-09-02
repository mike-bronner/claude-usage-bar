import SwiftUI
import XCTest
@testable import ClaudeUsageBar
@testable import ClaudeUsageBarCore

@MainActor
final class UsageMenuContentLayoutTests: XCTestCase {
    private static let live = Account(configDirectory: URL(filePath: "/tmp/.claude"), emailAddress: "me@x.com", organizationName: nil, accountUUID: "1")
    private static let idle = Account(configDirectory: URL(filePath: "/tmp/.claude-work"), emailAddress: "me@work.com", organizationName: "Work", accountUUID: "2")
    private static let usageJSON = Data(#"{"limits":[{"kind":"session","percent":23},{"kind":"weekly_all","percent":5},{"kind":"weekly_scoped","percent":1,"scope":{"model":{"display_name":"Opus"}}}]}"#.utf8)

    /// The live account answers with three limits; the idle one has never had a snapshot, so
    /// its block is a header and a notice — the shortest content the menu can show.
    private static func usage(_ account: Account) -> AccountUsage {
        account == live
            ? AccountUsage(subscriptionType: "max", rateLimitTier: nil, state: .live(rawUsage: usageJSON))
            : AccountUsage(subscriptionType: "team", rateLimitTier: nil, state: .idle(expiredAt: Date(timeIntervalSince1970: 1_799_990_000)))
    }

    private func model(accounts: [Account]) async -> UsageModel {
        let defaults = UserDefaults(suiteName: "UsageMenuContentLayoutTests.\(UUID().uuidString)")!
        let model = UsageModel(scan: { accounts }, fetch: Self.usage, defaults: defaults, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await model.refreshAll()
        return model
    }

    private func height(of model: UsageModel, selecting account: Account) -> CGFloat {
        model.selectedID = account.id
        return NSHostingView(rootView: UsageMenuContent(model: model)).fittingSize.height
    }

    /// The bug: picking the idle account inside the open menu left its short block floating in
    /// the middle of the live account's height. The fix holds the height at the tallest account
    /// so the native items below never move; this proves the height, not the alignment.
    func testItemHeightIsTheTallestAccountWhicheverIsSelected() async {
        let both = await model(accounts: [Self.live, Self.idle])
        let tall = height(of: both, selecting: Self.live)
        let short = height(of: both, selecting: Self.idle)
        XCTAssertEqual(short, tall, accuracy: 0.5, "switching account must not change the item height")

        let idleAlone = await model(accounts: [Self.idle])
        XCTAssertLessThan(height(of: idleAlone, selecting: Self.idle), tall - 40, "the idle block on its own must be clearly shorter, or the equality above proves nothing")
    }
}
