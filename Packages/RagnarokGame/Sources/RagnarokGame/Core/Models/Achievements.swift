//
//  Achievements.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation

/// The achievements of the character, as `ZC_ALL_ACH_LIST` and `ZC_ACH_UPDATE` send them.
///
/// The server only sends ids, progress counters, a completion time and a reward flag. Names and descriptions come
/// from the client script (`System/achievement_list.lub`) and are kept as ``Info`` by id. Without that script an
/// entry still works and shows as "Achievement #id".
struct Achievements: Equatable, Sendable {

    /// rAthena's `MAX_ACHIEVEMENT_OBJECTIVES`.
    static let objectiveCount = 10

    struct Entry: Identifiable, Equatable, Sendable {
        var id: UInt32
        var isCompleted: Bool

        /// The progress counters, always `objectiveCount` long.
        var progress: [Int]

        var completedAt: Date?
        var isRewardClaimed: Bool

        init(
            id: UInt32,
            isCompleted: Bool = false,
            progress: [Int] = [],
            completedAt: Date? = nil,
            isRewardClaimed: Bool = false
        ) {
            self.id = id
            self.isCompleted = isCompleted
            self.progress = Self.normalized(progress)
            self.completedAt = completedAt
            self.isRewardClaimed = isRewardClaimed
        }

        private static func normalized(_ progress: [Int]) -> [Int] {
            var progress = Array(progress.prefix(Achievements.objectiveCount))
            progress.append(contentsOf: repeatElement(0, count: Achievements.objectiveCount - progress.count))
            return progress
        }
    }

    /// The texts and rewards of one achievement, from the client script.
    struct Info: Equatable, Sendable {
        struct Objective: Equatable, Sendable {
            var text: String

            /// The value the matching counter must reach. Nil for a checklist row.
            var requiredCount: Int?
        }

        var title: String
        var summary: String
        var details: String

        /// The objective type, such as `ADVENTURE`.
        var group: String

        var objectives: [Objective]
        var rewardItemID: Int?
        var hasRewardTitle: Bool
        var hasRewardBuff: Bool
        var score: Int

        var hasReward: Bool {
            rewardItemID != nil || hasRewardTitle || hasRewardBuff
        }
    }

    /// What `ZC_ACH_UPDATE` reports about the level bar.
    struct Level: Equatable, Sendable {
        var totalPoints: Int
        var level: Int

        /// The points gained in the current level (the left number of the bar).
        var experience: Int

        /// The points the current level spans (the right number of the bar). Zero at the last level.
        var experienceToNextLevel: Int
    }

    enum Update: Equatable, Sendable {
        /// A bare level update, the server sends one at login before the list.
        case levelOnly

        /// The entry was not completed before, or not known, and is now. Not reported while loading.
        case completed(id: UInt32)

        case changed(id: UInt32)
    }

    /// In the order of the server: incomplete entries first, completed ones after.
    private(set) var entries: [Entry] = []
    private(set) var totalPoints = 0
    private(set) var level = 0
    private(set) var experience = 0
    private(set) var experienceToNextLevel = 0

    /// True once the server has sent the list, or the login level update.
    private(set) var isInitialized = false

    private(set) var info: [UInt32 : Info] = [:]
    private(set) var isCatalogRequested = false
    private(set) var pendingClaims: Set<UInt32> = []

    init() {
    }

    // MARK: - Reading

    func entry(id: UInt32) -> Entry? {
        entries.first(where: { $0.id == id })
    }

    func title(for id: UInt32) -> String {
        if let title = info[id]?.title, !title.isEmpty {
            return title
        }
        return "Achievement #\(id)"
    }

    var completedCount: Int {
        entries.filter(\.isCompleted).count
    }

    /// 0 to 1. A full bar at the last level, where the server sends no span.
    var levelFraction: Double {
        guard isInitialized else {
            return 0
        }
        guard experienceToNextLevel > 0 else {
            return 1
        }
        return min(max(Double(experience) / Double(experienceToNextLevel), 0), 1)
    }

    /// Whether the window should offer the reward button. An entry the script does not describe is offered
    /// because the server decides whether there is a reward.
    func hasClaimableReward(_ entry: Entry) -> Bool {
        guard entry.isCompleted, !entry.isRewardClaimed else {
            return false
        }
        return info[entry.id]?.hasReward ?? true
    }

    func isClaimPending(id: UInt32) -> Bool {
        pendingClaims.contains(id)
    }

    var claimableCount: Int {
        entries.filter(hasClaimableReward).count
    }

    // MARK: - Server updates

    /// Replaces everything with the list sent at login, and again after a title reward is claimed.
    mutating func apply(list entries: [Entry], level: Level) {
        self.entries = entries
        apply(level: level)
        isInitialized = true
        pendingClaims = pendingClaims.filter { id in
            entries.first(where: { $0.id == id })?.isRewardClaimed != true
        }
    }

    /// Applies a `ZC_ACH_UPDATE`. A nil entry is the bare update with only the level data.
    @discardableResult
    mutating func apply(update entry: Entry?, level: Level) -> Update {
        apply(level: level)

        guard let entry else {
            isInitialized = true
            return .levelOnly
        }

        let wasInitialized = isInitialized
        let previous = self.entry(id: entry.id)

        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            // The server keeps incomplete entries before the completed ones.
            let index = entry.isCompleted ? entries.endIndex : (entries.firstIndex(where: \.isCompleted) ?? entries.endIndex)
            entries.insert(entry, at: index)
        }

        if entry.isRewardClaimed {
            pendingClaims.remove(entry.id)
        }

        if wasInitialized, entry.isCompleted, previous?.isCompleted != true {
            return .completed(id: entry.id)
        }
        return .changed(id: entry.id)
    }

    // MARK: - Reward claims

    /// Marks a claim as sent. Returns false when there is nothing to claim or one is already on its way.
    mutating func beginClaim(id: UInt32) -> Bool {
        guard let entry = entry(id: id), entry.isCompleted, !entry.isRewardClaimed, !pendingClaims.contains(id) else {
            return false
        }
        pendingClaims.insert(id)
        return true
    }

    /// Applies `ZC_REQ_ACH_REWARD_ACK`.
    mutating func finishClaim(id: UInt32, succeeded: Bool) {
        pendingClaims.remove(id)
        if succeeded, let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isRewardClaimed = true
        }
    }

    // MARK: - Client script

    /// Returns true the first time, so the caller loads the script once.
    mutating func requestCatalog() -> Bool {
        guard !isCatalogRequested else {
            return false
        }
        isCatalogRequested = true
        return true
    }

    mutating func apply(catalog: [UInt32 : Info]) {
        info = catalog
    }

    // MARK: - Private

    private mutating func apply(level: Level) {
        totalPoints = level.totalPoints
        self.level = level.level
        experience = level.experience
        experienceToNextLevel = level.experienceToNextLevel
    }
}

// MARK: - Display

extension Achievements {

    /// The sections of the window.
    enum Filter: CaseIterable, Hashable, Sendable {
        case all
        case inProgress
        case completed
        case rewardReady
    }

    func entries(matching filter: Filter) -> [Entry] {
        switch filter {
        case .all:
            entries
        case .inProgress:
            entries.filter { !$0.isCompleted }
        case .completed:
            entries.filter(\.isCompleted)
        case .rewardReady:
            entries.filter(hasClaimableReward)
        }
    }

    /// Entries in window order: reward ready first, then in progress, then the rest, each by id.
    func sortedEntries(matching filter: Filter) -> [Entry] {
        func rank(_ entry: Entry) -> Int {
            if hasClaimableReward(entry) {
                0
            } else if !entry.isCompleted {
                1
            } else {
                2
            }
        }

        return entries(matching: filter).sorted { lhs, rhs in
            let (lhsRank, rhsRank) = (rank(lhs), rank(rhs))
            return lhsRank == rhsRank ? lhs.id < rhs.id : lhsRank < rhsRank
        }
    }

    /// Rows of progress text for an entry, such as `Poring 12/100` or `Find it`.
    func progressRows(for entry: Entry) -> [ProgressRow] {
        guard let info = info[entry.id], !info.objectives.isEmpty else {
            // Without the script only the counters the server fills in are known.
            return entry.progress.enumerated().compactMap { index, value in
                value > 0 ? ProgressRow(text: "Objective \(index + 1)", current: value, required: nil, isDone: entry.isCompleted) : nil
            }
        }

        return info.objectives.enumerated().map { index, objective in
            let current = index < entry.progress.count ? entry.progress[index] : 0
            let isDone: Bool
            if entry.isCompleted {
                isDone = true
            } else if let required = objective.requiredCount {
                isDone = current >= required
            } else {
                isDone = current > 0
            }
            return ProgressRow(text: objective.text, current: current, required: objective.requiredCount, isDone: isDone)
        }
    }

    struct ProgressRow: Equatable, Sendable {
        var text: String
        var current: Int

        /// Nil for a checklist row, which shows only a mark.
        var required: Int?

        var isDone: Bool
    }

    /// A readable form of the script's objective type, such as `Goal level` for `GOAL_LEVEL`.
    static func displayName(forGroup group: String) -> String {
        guard !group.isEmpty else {
            return "Other"
        }
        let words = group.split(separator: "_").map { $0.lowercased() }
        guard let first = words.first else {
            return "Other"
        }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}
