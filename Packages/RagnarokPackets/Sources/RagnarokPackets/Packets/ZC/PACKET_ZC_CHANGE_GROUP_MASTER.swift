//
//  PACKET_ZC_CHANGE_GROUP_MASTER.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_CHANGE_GROUP_MASTER: Int16 = 0x7fc

public struct PACKET_ZC_CHANGE_GROUP_MASTER: DecodablePacket {
    public static var size: Int {
        2 + 4 + 4
    }

    public var packetType: Int16
    public var AID: UInt32
    public var GID: UInt32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        AID = try decoder.decode(UInt32.self)
        GID = try decoder.decode(UInt32.self)
    }
}
