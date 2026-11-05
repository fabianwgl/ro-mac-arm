//
//  QuestLog.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import Observation

@Observable
final class QuestLog {
    struct Objective: Identifiable, Equatable, Sendable {
        var huntID: UInt32
        var huntID2: UInt32
        var monsterID: UInt32
        var monsterName: String
        var count: Int
        var required: Int

        var id: String {
            "\(huntID)-\(huntID2)-\(monsterID)"
        }

        fileprivate var key: ObjectiveKey {
            ObjectiveKey(huntID: huntID, huntID2: huntID2)
        }
    }

    struct Quest: Identifiable, Equatable, Sendable {
        var id: UInt32
        var isActive: Bool
        var timeLimit: TimeInterval?
        var objectives: [Objective]
    }

    struct Mission: Equatable, Sendable {
        var questID: UInt32
        var huntID: UInt32
        var huntID2: UInt32
        var monsterName: String
        var required: Int
    }

    fileprivate struct ObjectiveKey: Hashable {
        var huntID: UInt32
        var huntID2: UInt32
    }

    private(set) var quests: [UInt32 : Quest] = [:]

    private var missionsByQuest: [UInt32 : [ObjectiveKey : Mission]] = [:]

    var activeQuests: [Quest] {
        quests.values.filter(\.isActive).sorted { $0.id < $1.id }
    }

    var inactiveQuests: [Quest] {
        quests.values.filter { !$0.isActive }.sorted { $0.id < $1.id }
    }

    init() {
    }

    /// Replaces the whole quest log with the list sent when entering the map.
    func apply(allQuests: [Quest]) {
        var quests: [UInt32 : Quest] = [:]
        for var quest in allQuests {
            applyMissions(to: &quest)
            quests[quest.id] = quest
        }
        self.quests = quests
    }

    /// Stores the mission table, then fills in names and target counts for quests already received.
    func apply(missions: [Mission]) {
        for mission in missions {
            let key = ObjectiveKey(huntID: mission.huntID, huntID2: mission.huntID2)
            missionsByQuest[mission.questID, default: [:]][key] = mission
        }

        for questID in Array(quests.keys) {
            guard var quest = quests[questID] else {
                continue
            }
            applyMissions(to: &quest)
            quests[questID] = quest
        }
    }

    func add(_ quest: Quest) {
        var quest = quest
        applyMissions(to: &quest)
        quests[quest.id] = quest
    }

    func remove(questID: UInt32) {
        quests.removeValue(forKey: questID)
    }

    /// Updates the current hunt count. Values below zero or above the target are kept as sent.
    func updateHunt(questID: UInt32, huntID: UInt32, huntID2: UInt32, count: Int) {
        guard var quest = quests[questID] else {
            return
        }

        let key = ObjectiveKey(huntID: huntID, huntID2: huntID2)
        guard let index = quest.objectives.firstIndex(where: { $0.key == key }) else {
            return
        }

        quest.objectives[index].count = count
        quests[questID] = quest
    }

    func setActive(questID: UInt32, _ isActive: Bool) {
        guard var quest = quests[questID] else {
            return
        }

        quest.isActive = isActive
        quests[questID] = quest
    }

    private func applyMissions(to quest: inout Quest) {
        for index in quest.objectives.indices {
            guard let mission = missionsByQuest[quest.id]?[quest.objectives[index].key] else {
                continue
            }

            quest.objectives[index].monsterName = mission.monsterName
            quest.objectives[index].required = mission.required
        }
    }
}
