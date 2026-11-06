//
//  PACKET_ZC_REQ_ACH_REWARD_ACK.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_achievement_reward_ack`
///
/// rAthena writes `0a26 <result>.B <achievementID>.L`. The generated `packet_achievement_reward_ack` calls the
/// byte `failed`, but `achievement_get_reward` sends 1 on success and every refusal sends 0.
public struct PACKET_ZC_REQ_ACH_REWARD_ACK: DecodablePacket {
    public static var size: Int {
        2 + 1 + 4
    }

    public var packetType: Int16

    /// 1 when the reward was given, 0 when it was refused.
    public var result: UInt8

    public var achievementID: UInt32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        result = try decoder.decode(UInt8.self)
        achievementID = try decoder.decode(UInt32.self)
    }
}
