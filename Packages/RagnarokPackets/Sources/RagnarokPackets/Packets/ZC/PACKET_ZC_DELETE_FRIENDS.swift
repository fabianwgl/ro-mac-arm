//
//  PACKET_ZC_DELETE_FRIENDS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_ZC_DELETE_FRIENDS: Int16 = 0x20a

public struct PACKET_ZC_DELETE_FRIENDS: DecodablePacket {
    public static var size: Int {
        2 + 4 + 4
    }

    public var packetType: Int16
    public var AID: UInt32
    public var CID: UInt32

    public init(from decoder: BinaryDecoder) throws {
        packetType = try decoder.decode(Int16.self)
        AID = try decoder.decode(UInt32.self)
        CID = try decoder.decode(UInt32.self)
    }
}
