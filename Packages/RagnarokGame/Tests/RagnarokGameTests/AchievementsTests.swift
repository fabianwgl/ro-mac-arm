import Foundation
import Testing
@testable import RagnarokGame

struct AchievementsTests {
    @Test func applyListReplacesState() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1), entry(2, completed: true)], level: level(points: 10, level: 1, exp: 10, span: 100))
        achievements.apply(list: [entry(3)], level: level(points: 20, level: 2, exp: 5, span: 50))

        #expect(achievements.entries.map(\.id) == [3])
        #expect(achievements.totalPoints == 20)
        #expect(achievements.level == 2)
        #expect(achievements.experience == 5)
        #expect(achievements.experienceToNextLevel == 50)
        #expect(achievements.isInitialized)
    }

    @Test func entryPadsProgressToTenCounters() {
        let short = Achievements.Entry(id: 1, progress: [4])
        #expect(short.progress == [4, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        let long = Achievements.Entry(id: 2, progress: Array(1...12))
        #expect(long.progress == Array(1...10))
    }

    @Test func levelFraction() {
        var achievements = Achievements()
        #expect(achievements.levelFraction == 0)

        achievements.apply(list: [entry(1)], level: level(points: 50, level: 1, exp: 25, span: 100))
        #expect(achievements.levelFraction == 0.25)

        // rAthena sends a zero span at the last level.
        achievements.apply(list: [entry(1)], level: level(points: 5000, level: 20, exp: 300, span: 0))
        #expect(achievements.levelFraction == 1)

        achievements.apply(list: [entry(1)], level: level(points: 50, level: 1, exp: 500, span: 100))
        #expect(achievements.levelFraction == 1)
    }

    @Test func updateUpsertsEntryAndLevel() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1)], level: level(points: 0, level: 0, exp: 0, span: 10))

        let result = achievements.apply(update: entry(1, progress: [3]), level: level(points: 0, level: 0, exp: 0, span: 10))
        #expect(result == .changed(id: 1))
        #expect(achievements.entry(id: 1)?.progress[0] == 3)
        #expect(achievements.entries.count == 1)

        achievements.apply(update: entry(2), level: level(points: 0, level: 0, exp: 0, span: 10))
        #expect(achievements.entries.map(\.id) == [1, 2])
    }

    @Test func newEntriesKeepIncompleteBeforeCompleted() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1), entry(2, completed: true)], level: level(points: 10, level: 1, exp: 10, span: 100))

        achievements.apply(update: entry(3), level: level(points: 10, level: 1, exp: 10, span: 100))
        achievements.apply(update: entry(4, completed: true), level: level(points: 20, level: 1, exp: 20, span: 100))

        #expect(achievements.entries.map(\.id) == [1, 3, 2, 4])
    }

    @Test func completionIsReportedOnce() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1)], level: level(points: 0, level: 0, exp: 0, span: 10))

        let first = achievements.apply(update: entry(1, completed: true), level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(first == .completed(id: 1))
        #expect(achievements.totalPoints == 10)
        #expect(achievements.level == 1)

        let again = achievements.apply(update: entry(1, completed: true, claimed: true), level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(again == .changed(id: 1))
    }

    @Test func completionOfUnknownEntryIsReported() {
        var achievements = Achievements()
        achievements.apply(list: [], level: level(points: 0, level: 0, exp: 0, span: 10))

        let result = achievements.apply(update: entry(7, completed: true), level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(result == .completed(id: 7))
    }

    @Test func updatesBeforeTheLoginLevelUpdateAreSilent() {
        var achievements = Achievements()

        // rAthena completes achievements while loading, before the bare update and the list.
        let early = achievements.apply(update: entry(1, completed: true), level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(early == .changed(id: 1))
        #expect(achievements.isInitialized == false)

        let bare = achievements.apply(update: nil, level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(bare == .levelOnly)
        #expect(achievements.isInitialized)
        #expect(achievements.entries.map(\.id) == [1])

        // A character with no achievements gets no list, completions after the bare update are announced.
        let later = achievements.apply(update: entry(2, completed: true), level: level(points: 20, level: 1, exp: 10, span: 20))
        #expect(later == .completed(id: 2))
    }

    @Test func claimLifecycle() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1, completed: true), entry(2)], level: level(points: 10, level: 1, exp: 0, span: 20))

        let incomplete = achievements.beginClaim(id: 2)
        let unknown = achievements.beginClaim(id: 99)
        #expect(incomplete == false)
        #expect(unknown == false)

        let first = achievements.beginClaim(id: 1)
        let duplicate = achievements.beginClaim(id: 1)
        #expect(first)
        #expect(duplicate == false)
        #expect(achievements.isClaimPending(id: 1))

        achievements.finishClaim(id: 1, succeeded: false)
        #expect(achievements.isClaimPending(id: 1) == false)
        #expect(achievements.entry(id: 1)?.isRewardClaimed == false)

        let retry = achievements.beginClaim(id: 1)
        #expect(retry)
        achievements.finishClaim(id: 1, succeeded: true)
        #expect(achievements.entry(id: 1)?.isRewardClaimed == true)

        let afterClaim = achievements.beginClaim(id: 1)
        #expect(afterClaim == false)
    }

    @Test func updateWithRewardClearsPendingClaim() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1, completed: true)], level: level(points: 10, level: 1, exp: 0, span: 20))
        _ = achievements.beginClaim(id: 1)

        achievements.apply(update: entry(1, completed: true, claimed: true), level: level(points: 10, level: 1, exp: 0, span: 20))
        #expect(achievements.isClaimPending(id: 1) == false)
    }

    @Test func listWithTitleRewardClearsPendingClaim() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1, completed: true), entry(2, completed: true)], level: level(points: 20, level: 1, exp: 0, span: 20))
        _ = achievements.beginClaim(id: 1)
        _ = achievements.beginClaim(id: 2)

        // A title reward is answered with the whole list, not with an ack.
        achievements.apply(list: [entry(1, completed: true, claimed: true), entry(2, completed: true)], level: level(points: 20, level: 1, exp: 0, span: 20))
        #expect(achievements.isClaimPending(id: 1) == false)
        #expect(achievements.isClaimPending(id: 2))
    }

    @Test func claimableUsesScriptRewardWhenKnown() {
        var achievements = Achievements()
        achievements.apply(list: [
            entry(1, completed: true),
            entry(2, completed: true),
            entry(3, completed: true),
            entry(4, completed: true, claimed: true),
            entry(5)
        ], level: level(points: 30, level: 1, exp: 0, span: 20))
        achievements.apply(catalog: [
            1: info(title: "Rewarded", rewardItemID: 501),
            2: info(title: "No reward")
        ])

        #expect(achievements.hasClaimableReward(achievements.entry(id: 1)!))
        #expect(achievements.hasClaimableReward(achievements.entry(id: 2)!) == false)
        // The script does not describe 3, the server decides.
        #expect(achievements.hasClaimableReward(achievements.entry(id: 3)!))
        #expect(achievements.hasClaimableReward(achievements.entry(id: 4)!) == false)
        #expect(achievements.hasClaimableReward(achievements.entry(id: 5)!) == false)
        #expect(achievements.claimableCount == 2)
    }

    @Test func titleFallsBackToID() {
        var achievements = Achievements()
        #expect(achievements.title(for: 120001) == "Achievement #120001")

        achievements.apply(catalog: [120001: info(title: "North Field")])
        #expect(achievements.title(for: 120001) == "North Field")

        achievements.apply(catalog: [120001: info(title: "")])
        #expect(achievements.title(for: 120001) == "Achievement #120001")
    }

    @Test func catalogIsRequestedOnce() {
        var achievements = Achievements()
        let first = achievements.requestCatalog()
        let second = achievements.requestCatalog()
        #expect(first)
        #expect(second == false)
    }

    @Test func filtersAndOrder() {
        var achievements = Achievements()
        achievements.apply(list: [
            entry(10),
            entry(20, completed: true),
            entry(30, completed: true, claimed: true),
            entry(40, completed: true)
        ], level: level(points: 0, level: 0, exp: 0, span: 0))
        achievements.apply(catalog: [
            20: info(title: "a", rewardItemID: 501),
            30: info(title: "b", rewardItemID: 501),
            40: info(title: "c")
        ])

        #expect(achievements.entries(matching: .all).map(\.id) == [10, 20, 30, 40])
        #expect(achievements.entries(matching: .inProgress).map(\.id) == [10])
        #expect(achievements.entries(matching: .completed).map(\.id) == [20, 30, 40])
        #expect(achievements.entries(matching: .rewardReady).map(\.id) == [20])
        #expect(achievements.completedCount == 3)

        // Reward ready first, then in progress, then the rest.
        #expect(achievements.sortedEntries(matching: .all).map(\.id) == [20, 10, 30, 40])
    }

    @Test func progressRowsWithScript() {
        var achievements = Achievements()
        achievements.apply(list: [Achievements.Entry(id: 1, progress: [12, 1, 0])], level: level(points: 0, level: 0, exp: 0, span: 0))
        achievements.apply(catalog: [
            1: Achievements.Info(
                title: "t", summary: "s", details: "d", group: "BATTLE",
                objectives: [
                    .init(text: "Poring", requiredCount: 100),
                    .init(text: "Visit", requiredCount: nil),
                    .init(text: "Never", requiredCount: nil)
                ],
                rewardItemID: nil, hasRewardTitle: false, hasRewardBuff: false, score: 10
            )
        ])

        let rows = achievements.progressRows(for: achievements.entry(id: 1)!)
        #expect(rows == [
            .init(text: "Poring", current: 12, required: 100, isDone: false),
            .init(text: "Visit", current: 1, required: nil, isDone: true),
            .init(text: "Never", current: 0, required: nil, isDone: false)
        ])
    }

    @Test func progressRowsWithoutScriptListNonZeroCounters() {
        var achievements = Achievements()
        achievements.apply(list: [Achievements.Entry(id: 1, progress: [0, 5, 0, 2])], level: level(points: 0, level: 0, exp: 0, span: 0))

        let rows = achievements.progressRows(for: achievements.entry(id: 1)!)
        #expect(rows.map(\.current) == [5, 2])
        #expect(rows.allSatisfy { $0.required == nil && !$0.isDone })
    }

    @Test func completedEntryShowsEveryRowDone() {
        var achievements = Achievements()
        achievements.apply(list: [entry(1, completed: true)], level: level(points: 0, level: 0, exp: 0, span: 0))
        achievements.apply(catalog: [
            1: Achievements.Info(
                title: "t", summary: "s", details: "d", group: "BATTLE",
                objectives: [.init(text: "Poring", requiredCount: 100)],
                rewardItemID: nil, hasRewardTitle: false, hasRewardBuff: false, score: 10
            )
        ])

        let rows = achievements.progressRows(for: achievements.entry(id: 1)!)
        #expect(rows.first?.isDone == true)
    }

    @Test func groupDisplayNames() {
        #expect(Achievements.displayName(forGroup: "ADVENTURE") == "Adventure")
        #expect(Achievements.displayName(forGroup: "GOAL_LEVEL") == "Goal level")
        #expect(Achievements.displayName(forGroup: "") == "Other")
    }

    // MARK: - Helpers

    private func entry(_ id: UInt32, completed: Bool = false, claimed: Bool = false, progress: [Int] = []) -> Achievements.Entry {
        Achievements.Entry(
            id: id,
            isCompleted: completed,
            progress: progress,
            completedAt: completed ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            isRewardClaimed: claimed
        )
    }

    private func level(points: Int, level: Int, exp: Int, span: Int) -> Achievements.Level {
        Achievements.Level(totalPoints: points, level: level, experience: exp, experienceToNextLevel: span)
    }

    private func info(title: String, rewardItemID: Int? = nil) -> Achievements.Info {
        Achievements.Info(
            title: title, summary: "", details: "", group: "BATTLE", objectives: [],
            rewardItemID: rewardItemID, hasRewardTitle: false, hasRewardBuff: false, score: 10
        )
    }
}
