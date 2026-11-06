//
//  AchievementList.swift
//  RagnarokScript
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import RagnarokResources

/// The achievement texts of the kRO client, from `System/achievement_list.lub`.
///
/// The server only sends achievement ids with their progress. The title, description, objective names,
/// required counts and rewards live in this client script.
final public class AchievementList: Resource {
    public let entries: [Int : AchievementList.Entry]

    init(entries: [Int : AchievementList.Entry] = [:]) {
        self.entries = entries
    }

    public func entry(forID id: Int) -> AchievementList.Entry? {
        entries[id]
    }
}

extension AchievementList {

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: Int

        /// The objective type, such as `ADVENTURE`, `BATTLE` or `GOAL_LEVEL`.
        public var group: String

        /// The tab the kRO window lists this achievement under.
        public var major: Int
        public var minor: Int

        public var title: String
        public var summary: String
        public var details: String

        /// One row per progress counter the server sends (`objective[0]`, `objective[1]`, ...).
        public var objectives: [AchievementList.Objective]

        public var reward: AchievementList.Reward

        /// The achievement points, which the server also counts.
        public var score: Int

        /// 1 for achievements that show a progress bar with ranks instead of a checklist.
        public var uiType: Int
    }

    public struct Objective: Equatable, Sendable {
        public var text: String

        /// The value the matching counter must reach. Nil for a plain checklist row.
        public var requiredCount: Int?

        /// The achievement that tracks this row, for rows that point at another achievement.
        public var shortcutID: Int?
    }

    public struct Reward: Equatable, Sendable {
        public var itemID: Int?
        public var titleID: Int?
        public var buffID: Int?

        public var isEmpty: Bool {
            itemID == nil && titleID == nil && buffID == nil
        }
    }
}

extension ResourceManager {

    /// Loads `System/achievement_list.lub` from the client files. Empty when the client has no such file.
    public func achievementList() async -> AchievementList {
        await cachedResource(forIdentifier: "AchievementList") { [self] in
            do {
                let data = try await contentsOfResource(at: AchievementListLoader.path)
                return AchievementListLoader().achievementList(from: data)
            } catch {
                logger.warning("\(error)")
                return AchievementList()
            }
        }
    }
}
