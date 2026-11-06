//
//  PACKET_ZC_ACH_UPDATE.swift
//  RagnarokPackets
//
//  Created by Leon Li on 2024/8/28.
//

import BinaryIO

/// See `clif_achievement_update`
///
/// rAthena writes `0a24 <totalPoints>.L <level>.W <experience>.L <experienceToNextLevel>.L` followed by one
/// ``ach_list_info``. Without an achievement (login) the entry is all zero, so only the totals carry data.
public struct PACKET_ZC_ACH_UPDATE: DecodablePacket {
    public static var size: Int {
        2 + 4 + 2 + 4 + 4 + ach_list_info.size
    }

    public var packetType: Int16
    public var totalPoints: UInt32
    public var level: UInt16

    /// The points gained in the current level (the left number of the bar).
    public var experience: UInt32

    /// The points the current level spans (the right number of the bar). Zero at the last level.
    public var experienceToNextLevel: UInt32

    public var achievement: ach_list_info

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        totalPoints = try decoder.decode(UInt32.self)
        level = try decoder.decode(UInt16.self)
        experience = try decoder.decode(UInt32.self)
        experienceToNextLevel = try decoder.decode(UInt32.self)
        achievement = try decoder.decode(ach_list_info.self)
    }
}
