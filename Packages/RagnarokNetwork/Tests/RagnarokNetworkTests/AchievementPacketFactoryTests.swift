//
//  AchievementPacketFactoryTests.swift
//  RagnarokNetworkTests
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import Foundation
import RagnarokNetwork
import RagnarokPackets
import Testing

@Suite("Achievement packet factory")
struct AchievementPacketFactoryTests {
    @Test func rewardRequestPacket() throws {
        let packet = PacketFactory.CZ_REQ_ACH_REWARD(achievementID: 120001)

        #expect(packet.packetType == HEADER_CZ_REQ_ACH_REWARD)
        #expect(packet.achievementID == 120001)

        // 0a25 <achievementID>.L, 6 bytes in rAthena's packet table.
        let data = try PacketEncoder().encode(packet)
        #expect([UInt8](data) == [0x25, 0x0a, 0xc1, 0xd4, 0x01, 0x00])
    }
}
