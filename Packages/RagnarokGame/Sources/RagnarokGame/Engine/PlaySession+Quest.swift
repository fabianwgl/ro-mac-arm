//
//  PlaySession+Quest.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokPackets

extension PlaySession {
    /// Handles quest packets. Returns false when the packet is not a quest packet.
    @discardableResult
    func handleQuestPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_ALL_QUEST_LIST:
            questLog.apply(allQuests: packet.quests.map(quest(from:)))
        case let packet as PACKET_ZC_ALL_QUEST_MISSION:
            questLog.apply(missions: packet.missions.map(mission(from:)))
        case let packet as packet_quest_add_header:
            questLog.add(quest(from: packet))
        case let packet as PACKET_ZC_DEL_QUEST:
            questLog.remove(questID: packet.questID)
        case let packet as packet_quest_update_header:
            for objective in packet.objectives {
                questLog.updateHunt(
                    questID: objective.questID,
                    huntID: objective.huntIdent,
                    huntID2: objective.huntIdent2,
                    count: Int(objective.count)
                )
            }
        case let packet as PACKET_ZC_ACTIVE_QUEST:
            questLog.setActive(questID: packet.questID, packet.active != 0)
        default:
            return false
        }
        return true
    }

    private func quest(from packet: PACKET_ZC_ALL_QUEST_LIST_sub) -> QuestLog.Quest {
        QuestLog.Quest(
            id: packet.questID,
            isActive: packet.active != 0,
            timeLimit: timeLimit(serverTime: packet.questServerTime, endTime: packet.questEndTime),
            objectives: packet.objectives.map(objective(from:))
        )
    }

    private func quest(from packet: packet_quest_add_header) -> QuestLog.Quest {
        QuestLog.Quest(
            id: packet.questID,
            isActive: packet.active != 0,
            timeLimit: timeLimit(serverTime: packet.quest_svrTime, endTime: packet.quest_endTime),
            objectives: packet.objectives.map(objective(from:))
        )
    }

    private func objective(from packet: packet_quest_hunt_sub) -> QuestLog.Objective {
        let count = Int(packet.huntCount)
        return QuestLog.Objective(
            huntID: packet.huntIdent,
            huntID2: packet.huntIdent2,
            monsterID: packet.mob_id,
            monsterName: packet.mobName,
            count: count,
            required: count
        )
    }

    private func mission(from packet: packet_mission_info_sub) -> QuestLog.Mission {
        QuestLog.Mission(
            questID: packet.huntIdent,
            huntID: packet.huntIdent,
            huntID2: packet.huntIdent2,
            monsterName: packet.mobName,
            required: Int(packet.maxCount > 0 ? packet.maxCount : packet.huntCount)
        )
    }

    private func timeLimit(serverTime: Int32, endTime: Int32) -> TimeInterval? {
        guard endTime > 0 else {
            return nil
        }
        return TimeInterval(max(Int64(endTime) - Int64(serverTime), 0))
    }
}
