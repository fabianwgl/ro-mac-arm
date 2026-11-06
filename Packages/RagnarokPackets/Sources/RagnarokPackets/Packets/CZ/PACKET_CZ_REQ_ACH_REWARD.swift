//
//  PACKET_CZ_REQ_ACH_REWARD.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_CZ_REQ_ACH_REWARD: Int16 = 0xa25

/// See `clif_parse_AchievementCheckReward`
public struct PACKET_CZ_REQ_ACH_REWARD: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_REQ_ACH_REWARD
    public var achievementID: UInt32 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(achievementID)
    }
}
