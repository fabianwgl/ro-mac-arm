//
//  PACKET_CZ_DELETE_FRIENDS.swift
//  RagnarokPackets
//
//  RO Mac Client. SPDX-License-Identifier: GPL-3.0
//

import BinaryIO

public let HEADER_CZ_DELETE_FRIENDS: Int16 = 0x203

public struct PACKET_CZ_DELETE_FRIENDS: EncodablePacket {
    public var packetType: Int16 = HEADER_CZ_DELETE_FRIENDS
    public var AID: UInt32 = 0
    public var CID: UInt32 = 0

    public init() {
    }

    public func encode(to encoder: BinaryEncoder) throws {
        try encoder.encode(packetType)
        try encoder.encode(AID)
        try encoder.encode(CID)
    }
}
