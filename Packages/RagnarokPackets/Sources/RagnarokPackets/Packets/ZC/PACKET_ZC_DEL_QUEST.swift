//
//  PACKET_ZC_DEL_QUEST.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_DEL_QUEST: Int16 = 0x2b4

/// See `clif_quest_delete`
public struct PACKET_ZC_DEL_QUEST: DecodablePacket {
    public static var size: Int {
        2 + 4
    }

    public var packetType: Int16
    public var questID: UInt32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        questID = try decoder.decode(UInt32.self)
    }
}
