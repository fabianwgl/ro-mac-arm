//
//  PlaySession+Achievements.swift
//  RagnarokGame
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import RagnarokResources
import RagnarokScript

extension PlaySession {

    /// Handles achievement packets. Returns false when the packet is not an achievement packet.
    ///
    /// rAthena (`clif_achievement_list_all`, `clif_achievement_update`, `clif_achievement_reward_ack`) sends the
    /// list and a bare level update when the character logs in, an update for every progress or completion, and
    /// an ack for every reward claim. There is no packet to ask for the list.
    func handleAchievementPacket(_ packet: any DecodablePacket) -> Bool {
        switch packet {
        case let packet as PACKET_ZC_ALL_ACH_LIST:
            loadAchievementCatalogIfNeeded()
            achievements.apply(
                list: packet.achievements.map(achievementEntry(from:)),
                level: Achievements.Level(
                    totalPoints: Int(packet.totalPoints),
                    level: Int(packet.level),
                    experience: Int(packet.experience),
                    experienceToNextLevel: Int(packet.experienceToNextLevel)
                )
            )
        case let packet as PACKET_ZC_ACH_UPDATE:
            handleAchievementUpdate(packet)
        case let packet as PACKET_ZC_REQ_ACH_REWARD_ACK:
            handleAchievementRewardAck(packet)
        default:
            return false
        }
        return true
    }

    // MARK: - Requests

    /// Asks the server for the reward of a completed achievement (`CZ_REQ_ACH_REWARD`).
    /// The answer is `ZC_REQ_ACH_REWARD_ACK`, and an update with the reward flag set.
    func claimAchievementReward(id: UInt32) {
        guard achievements.beginClaim(id: id) else {
            return
        }

        sendPacket(PacketFactory.CZ_REQ_ACH_REWARD(achievementID: id))

        // The server answers every claim, but do not leave the button disabled if it never does.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, achievements.isClaimPending(id: id) else {
                return
            }
            achievements.finishClaim(id: id, succeeded: false)
        }
    }

    // MARK: - Packet Handling

    private func handleAchievementUpdate(_ packet: PACKET_ZC_ACH_UPDATE) {
        loadAchievementCatalogIfNeeded()

        let level = Achievements.Level(
            totalPoints: Int(packet.totalPoints),
            level: Int(packet.level),
            experience: Int(packet.experience),
            experienceToNextLevel: Int(packet.experienceToNextLevel)
        )

        // Without an achievement the server zero-fills the entry, id 0 is none.
        let entry = packet.achievement.ach_id == 0 ? nil : achievementEntry(from: packet.achievement)

        if case .completed(let id) = achievements.apply(update: entry, level: level) {
            let points = achievements.info[id]?.score
            var content = "Achievement completed: \(achievements.title(for: id))"
            if let points, points > 0 {
                content += " (+\(points) points)"
            }
            addAchievementMessage(content)
        }
    }

    private func handleAchievementRewardAck(_ packet: PACKET_ZC_REQ_ACH_REWARD_ACK) {
        let id = packet.achievementID
        let succeeded = packet.result != 0
        achievements.finishClaim(id: id, succeeded: succeeded)

        if succeeded {
            addAchievementMessage("Achievement reward claimed: \(achievements.title(for: id))")
        } else {
            addAchievementMessage("Could not claim the reward of \(achievements.title(for: id)).", type: .error)
        }
    }

    // MARK: - Client Script

    /// Loads the titles and descriptions once. The window works without them.
    private func loadAchievementCatalogIfNeeded() {
        guard achievements.requestCatalog() else {
            return
        }

        let resourceManager = context.resourceManager
        Task { [weak self] in
            let list = await resourceManager.achievementList()
            guard let self else {
                return
            }
            achievements.apply(catalog: Self.achievementCatalog(from: list))
        }
    }

    nonisolated static func achievementCatalog(from list: AchievementList) -> [UInt32 : Achievements.Info] {
        var catalog: [UInt32 : Achievements.Info] = [:]
        for (id, entry) in list.entries {
            guard let id = UInt32(exactly: id) else {
                continue
            }
            catalog[id] = Achievements.Info(
                title: entry.title,
                summary: entry.summary,
                details: entry.details,
                group: entry.group,
                objectives: entry.objectives.map {
                    Achievements.Info.Objective(text: $0.text, requiredCount: $0.requiredCount)
                },
                rewardItemID: entry.reward.itemID,
                hasRewardTitle: entry.reward.titleID != nil,
                hasRewardBuff: entry.reward.buffID != nil,
                score: entry.score
            )
        }
        return catalog
    }

    // MARK: - Packet Conversion

    private func achievementEntry(from info: ach_list_info) -> Achievements.Entry {
        Achievements.Entry(
            id: info.ach_id,
            isCompleted: info.completed != 0,
            progress: info.objective.map { Int($0) },
            completedAt: info.completed_at > 0 ? Date(timeIntervalSince1970: TimeInterval(info.completed_at)) : nil,
            isRewardClaimed: info.reward != 0
        )
    }

    private func addAchievementMessage(_ content: String, type: MessageCenter.MessageType = .system) {
        let message = MessageCenter.Message(content: content, type: type, category: .general)
        messageCenter.messages.append(message)
    }
}
