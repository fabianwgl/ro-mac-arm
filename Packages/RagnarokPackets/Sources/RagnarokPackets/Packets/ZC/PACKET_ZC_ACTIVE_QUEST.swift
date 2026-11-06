//
//  PACKET_ZC_ACTIVE_QUEST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_ACTIVE_QUEST: Int16 = 0x2b7

/// See `clif_quest_update_status`
public struct PACKET_ZC_ACTIVE_QUEST: DecodablePacket {
    public static var size: Int {
        2 + 4 + 1
    }

    public var packetType: Int16
    public var questID: UInt32
    public var active: UInt8

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        questID = try decoder.decode(UInt32.self)
        active = try decoder.decode(UInt8.self)
    }
}
