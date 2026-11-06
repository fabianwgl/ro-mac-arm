//
//  PACKET_ZC_ALL_ACH_LIST.swift
//  RagnarokPackets
//
//  Created by Leon Li on 2024/8/28.
//

import BinaryIO

/// See `clif_achievement_list_all`
///
/// rAthena writes `0a23 <packetLength>.W <count>.L <totalPoints>.L <level>.W <experience>.L <experienceToNextLevel>.L`
/// (22 bytes) followed by `count` entries of ``ach_list_info`` (50 bytes each).
/// It sends nothing when the character has no achievement at all.
public struct PACKET_ZC_ALL_ACH_LIST: DecodablePacket {
    public static var size: Int {
        -1
    }

    static let headerLength = 2 + 2 + 4 + 4 + 2 + 4 + 4

    public var packetType: Int16
    public var packetLength: Int16
    public var achievementCount: UInt32
    public var totalPoints: UInt32
    public var level: UInt16

    /// The points gained in the current level (the left number of the bar).
    public var experience: UInt32

    /// The points the current level spans (the right number of the bar). Zero at the last level.
    public var experienceToNextLevel: UInt32

    public var achievements: [ach_list_info]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)
        achievementCount = try decoder.decode(UInt32.self)
        totalPoints = try decoder.decode(UInt32.self)
        level = try decoder.decode(UInt16.self)
        experience = try decoder.decode(UInt32.self)
        experienceToNextLevel = try decoder.decode(UInt32.self)

        // Trust the length field over the count field: it is what framed the packet.
        let entryCount = max(Int(packetLength) - Self.headerLength, 0) / ach_list_info.size
        let count = min(Int(achievementCount), entryCount)
        achievements = try decoder.decode([ach_list_info].self, count: count)
    }
}
