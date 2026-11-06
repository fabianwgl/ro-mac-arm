//
//  PACKET_ZC_ALL_QUEST_LIST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

/// See `clif_quest_send_list`
public struct PACKET_ZC_ALL_QUEST_LIST: DecodablePacket {
    public static var size: Int {
        -1
    }

    public var packetType: Int16
    public var packetLength: Int16
    public var quests: [PACKET_ZC_ALL_QUEST_LIST_sub]

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        packetLength = try decoder.decode(Int16.self)
        let questCount = try decoder.decode(Int32.self)

        quests = []
        for _ in 0..<max(Int(questCount), 0) {
            quests.append(try decoder.decode(PACKET_ZC_ALL_QUEST_LIST_sub.self))
        }
    }
}

public struct PACKET_ZC_ALL_QUEST_LIST_sub: BinaryDecodable, Sendable {
    public var questID: UInt32
    public var active: UInt8
    public var questServerTime: Int32
    public var questEndTime: Int32
    public var objectives: [packet_quest_hunt_sub]

    public init(from decoder: BinaryDecoder) throws {
        questID = try decoder.decode(UInt32.self)
        active = try decoder.decode(UInt8.self)
        questServerTime = try decoder.decode(Int32.self)
        questEndTime = try decoder.decode(Int32.self)

        let count = try decoder.decode(Int16.self)
        objectives = try decoder.decode([packet_quest_hunt_sub].self, count: max(Int(count), 0))
    }
}
