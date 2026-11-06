//
//  PACKET_ZC_ALL_QUEST_MISSION.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_ALL_QUEST_MISSION: Int16 = 0x2b2

/// See `clif_quest_send_mission`
public struct PACKET_ZC_ALL_QUEST_MISSION: DecodablePacket {
    public static var size: Int {
        -1
    }

    public var packetType: Int16
    public var packetLength: Int16
    public var missions: [packet_mission_info_sub]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)

        let count = max(Int(packetLength) - 4, 0) / packet_mission_info_sub.size
        missions = try decoder.decode([packet_mission_info_sub].self, count: count)
    }
}
